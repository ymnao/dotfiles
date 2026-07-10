#!/usr/bin/env bash
#
# Stop hook (Claude Code): ターン終了前の検証ゲート
# 正本: agents/hooks/stop-verify-gate.sh
# (PR6 適用後は claude/hooks/ から相対 symlink。PR6 未適用なら claude/hooks/ に直接配置)
#
# 発動条件 (すべて満たすときのみ検証を実行。それ以外は即 exit 0 = fail-open):
#   1. stdin JSON の cwd が git リポジトリ内
#   2. リポジトリルートに .claude/stop-gate.conf が存在する (明示オプトイン)
#   3. conf に検証コマンドが書かれている (先頭の非コメント・非空行 1 行)
#   4. 作業ツリーに変更がある (チャットのみのターンでテストを回さない)
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
# セキュリティ前提: stop-gate.conf のコマンドはリポジトリの Makefile と同じ信頼レベル
# (リポジトリ内ファイルの実行)。信頼しないリポジトリには conf を置かないこと。
#
# 依存: jq / git (無ければ fail-open)

set -uo pipefail

input=$(cat)

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -n "$cwd" ] || cwd=$(pwd -P)
[ -d "$cwd" ] || exit 0

repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0

conf="$repo_root/.claude/stop-gate.conf"
[ -f "$conf" ] || exit 0

# 先頭の非コメント・非空行 1 行を検証コマンドとして採用
gate_cmd=$(grep -vE '^[[:space:]]*(#|$)' "$conf" | head -1)
[ -n "$gate_cmd" ] || exit 0

# 作業ツリーが clean なら検証しない (追跡外ファイルも変更とみなす)
[ -n "$(git -C "$repo_root" status --porcelain 2>/dev/null)" ] || exit 0

# 連続ブロックカウンタ (セッション単位、TMPDIR に保持)
# session_id は外部入力なのでパスに埋め込む前に [A-Za-z0-9._-] へ正規化する
# (/ や .. を含む値で TMPDIR 外に書き込まないための防御)
session_id=$(printf '%s' "$input" | jq -r '.session_id // "unknown"' | tr -c 'A-Za-z0-9._-' '_')
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

output=$( (cd "$repo_root" && eval "$gate_cmd") 2>&1 )
status=$?
if [ "$status" -eq 0 ]; then
  rm -f "$count_file"
  exit 0
fi

echo $((count + 1)) >"$count_file"
tail_output=$(printf '%s\n' "$output" | tail -20)
cat >&2 <<EOF
[stop-verify-gate] 検証コマンドが失敗しました (exit $status): $gate_cmd
修正してから終了してください。失敗出力 (末尾 20 行):
$tail_output
EOF
exit 2
