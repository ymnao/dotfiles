#!/usr/bin/env bash
#
# Stop hook (Claude Code): ターン終了前の検証ゲート
# 正本: agents/hooks/stop-verify-gate.sh
# (PR6 適用後は claude/hooks/ から相対 symlink。PR6 未適用なら claude/hooks/ に直接配置)
#
# 発動条件 (すべて満たすときのみ検証を実行。それ以外は即 exit 0 = fail-open):
#   1. stdin JSON の hook_event_name が "Stop"
#   2. stdin JSON の cwd が git リポジトリ内
#   3. リポジトリルートに .claude/stop-gate.conf が存在する (明示オプトイン)
#   4. conf に検証コマンドが書かれている (先頭の非コメント・非空行 1 行のみを採用。
#      2 行目以降は無視される。複数コマンドを回したいときは && で 1 行につなぐ)
#   5. 作業ツリーに変更がある (チャットのみのターンでテストを回さない)
#
# 判定:
#   - 検証コマンド exit 0 → exit 0 (ターン終了を許可)
#   - 非 0             → exit 2 + stderr (ターン終了をブロックし、失敗出力を Claude に返す)
#
# ループ防止 (二重):
#   - セッションごとの連続ブロックカウンタ: 3 回連続でブロックしたら fail-open に切り替え、
#     手動確認を促す (検証が pass したらリセット)
#   - Claude Code 本体の 8 回 block cap が最終安全弁
#   - 入力の stop_hook_active はチェックのみに使わない: ブロック後の続行ターンでも
#     修正結果を再検証したいため (再検証しないと「直しました」報告だけで抜けられる)
#
# 検証コマンドの実行:
#   - 常に fresh な `bash -c` で実行する。この hook の set -u/pipefail は継承しない
#     (conf 内の unset var 参照などで意図せず fail させないため)
#   - perl でタイムアウト (デフォルト 300 秒、STOP_GATE_TIMEOUT_SECS で上書き可)。
#     子を独立プロセスグループにし、alarm 発火でグループごと TERM → KILL する
#     (孫プロセスまで確実に落とし、パイプ hang と harness 10 分 timeout の silent pass を防ぐ)
#   - GUI 起動時 (Raycast 等) に不足しがちな Homebrew の PATH を末尾補完する
#
# セキュリティ前提: stop-gate.conf のコマンドはリポジトリの Makefile と同じ信頼レベル
# (リポジトリ内ファイルの実行)。信頼しないリポジトリには conf を置かないこと。
#
# 依存: jq / git (無ければ fail-open)。perl があればタイムアウト有効

set -uo pipefail

input=""
IFS= read -r -t 10 -d '' input || true

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

# jq は 1 回だけ fork し、event / cwd / session_id をまとめて取り出す
vals=$(printf '%s' "$input" | jq -r '.hook_event_name // "", .cwd // "", .session_id // "unknown"' 2>/dev/null) || exit 0
{
  IFS= read -r event
  IFS= read -r cwd
  IFS= read -r session_id
} <<EOF
$vals
EOF

# Stop 以外のイベント (JSON 壊れで event 空を含む) は即 fail-open
[ "$event" = "Stop" ] || exit 0

[ -n "$cwd" ] || cwd=$(pwd -P)
[ -d "$cwd" ] || exit 0

repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0

conf="$repo_root/.claude/stop-gate.conf"
[ -f "$conf" ] || exit 0

# 先頭の非コメント・非空行 1 行を検証コマンドとして採用。
# awk 1 プロセスで CRLF 除去・空行/コメント行スキップ・1 行採用を行う
# (grep|head のパイプは SIGPIPE 141 や CRLF 無音失敗を起こしうるため)。
gate_cmd=$(awk '{ sub(/\r$/, "") } NF == 0 { next } $1 ~ /^#/ { next } { print; exit }' "$conf")
[ -n "$gate_cmd" ] || exit 0

# 作業ツリーが clean なら検証しない (追跡外ファイルも変更とみなす)
[ -n "$(git -C "$repo_root" status --porcelain 2>/dev/null)" ] || exit 0

# session_id をカウンタファイルパスに使う前にサニタイズ (パストラバーサル防御)
case "$session_id" in ''|*[!A-Za-z0-9-]*) session_id=unknown ;; esac

# 連続ブロックカウンタ (セッション単位、TMPDIR に保持)
count_file="${TMPDIR:-/tmp}/stop-gate.${session_id}.count"
count=0
if [ -f "$count_file" ]; then
  count=$(cat "$count_file" 2>/dev/null || printf '0')
fi
case "$count" in
  ''|*[!0-9]*) count=0 ;;
esac
if [ "$count" -ge 3 ]; then
  echo "[stop-verify-gate] 3 回連続でブロックしたため検証をスキップします。手動で確認してください: $gate_cmd" >&2
  rm -f "$count_file"
  exit 0
fi

# Homebrew PATH 補完 (GUI 起動時に不足する。末尾追加で既存 PATH を優先)
for d in /opt/homebrew/bin /usr/local/bin; do
  case ":$PATH:" in *":$d:"*) ;; *) PATH="$PATH:$d" ;; esac
done
export PATH

# 検証コマンドを fresh な bash -c で実行 (set -u/pipefail を継承させない)。
# perl でタイムアウト監視: 子を独立プロセスグループにして fork し、alarm 発火時は
# グループごと TERM → KILL (孫プロセスが stdout パイプを握ったまま orphan になり
# コマンド置換が hang するのを防ぐ)。タイムアウト時は status 142。
timeout_secs="${STOP_GATE_TIMEOUT_SECS:-300}"
if command -v perl >/dev/null 2>&1; then
  output=$( (cd "$repo_root" && perl -e '
    my $t = shift;
    my $pid = fork;
    exit 127 unless defined $pid;
    if ($pid == 0) { setpgrp(0, 0); exec @ARGV; exit 127 }
    $SIG{ALRM} = sub { kill "TERM", -$pid; sleep 2; kill "KILL", -$pid; exit 142 };
    alarm $t;
    waitpid($pid, 0);
    alarm 0;
    exit(($? & 127) ? 128 + ($? & 127) : $? >> 8);
  ' "$timeout_secs" bash -c "$gate_cmd") 2>&1 )
else
  output=$( (cd "$repo_root" && bash -c "$gate_cmd") 2>&1 )
fi
status=$?
if [ "$status" -eq 0 ]; then
  rm -f "$count_file"
  exit 0
fi

echo $((count + 1)) >"$count_file"
tail_output=$(printf '%s\n' "$output" | tail -n 20)
timeout_note=""
if [ "$status" -eq 142 ]; then
  timeout_note="(タイムアウト ($timeout_secs 秒) の可能性)"
fi
cat >&2 <<EOF
[stop-verify-gate] 検証コマンドが失敗しました (exit $status)$timeout_note: $gate_cmd
修正してから終了してください。失敗出力 (末尾 20 行):
$tail_output
EOF
exit 2
