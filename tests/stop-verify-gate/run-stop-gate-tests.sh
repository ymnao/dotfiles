#!/usr/bin/env bash
set -uo pipefail

# stop-verify-gate.sh のシナリオテスト。
# 各シナリオで一時 git リポジトリを作り、Stop hook 入力 JSON を流して
# exit code (0=許可 / 2=ブロック) を検証する。
#
# 使い方: run-stop-gate-tests.sh
#   環境変数 HOOK_PATH で hook の場所を上書きできる
#   (デフォルト: <リポジトリルート>/claude/hooks/stop-verify-gate.sh)
#
# 依存: bash 3.2+ / jq / git

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
HOOK="${HOOK_PATH:-$REPO_ROOT/claude/hooks/stop-verify-gate.sh}"

if [ ! -f "$HOOK" ]; then
  echo "ERROR: hook not found: $HOOK (HOOK_PATH で上書き可)" >&2
  exit 1
fi
for tool in jq git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool is required" >&2; exit 1; }
done

BASE="$(mktemp -d "${TMPDIR:-/tmp}/stop-gate-tests.XXXXXX")"
cleanup() { [ -n "${BASE:-}" ] && rm -rf "$BASE"; }
trap cleanup EXIT

pass=0
fail=0

# 一時 git リポジトリを作る。$1=名前。作成先パスを echo する
make_repo() {
  local dir="$BASE/$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "test"
  printf '%s' "$dir"
}

# hook を実行して exit code を返す。$1=cwd, $2=session_id
# カウンタの TMPDIR はシナリオ間で共有しないよう BASE 配下に固定
run_gate() {
  local json rc=0
  json=$(jq -cn --arg cwd "$1" --arg sid "$2" \
    '{"session_id":$sid,"hook_event_name":"Stop","stop_hook_active":false,"cwd":$cwd}')
  printf '%s' "$json" | TMPDIR="$BASE/hook-tmp" bash "$HOOK" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

check() {
  # $1=テスト名, $2=期待 exit code, $3=実際
  if [ "$3" = "$2" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $1: expected=$2 got=$3"
    fail=$((fail + 1))
  fi
}

# hook を実行し exit code と stderr の期待パターンを両方検証する。
# $1=テスト名, $2=cwd, $3=session_id, $4=期待 exit code, $5=grep パターン
check_stderr_contains() {
  local json out rc=0
  json=$(jq -cn --arg cwd "$2" --arg sid "$3" \
    '{"session_id":$sid,"hook_event_name":"Stop","stop_hook_active":false,"cwd":$cwd}')
  out=$(printf '%s' "$json" | TMPDIR="$BASE/hook-tmp" bash "$HOOK" 2>&1 >/dev/null) || rc=$?
  if [ "$rc" = "$4" ] && printf '%s' "$out" | grep -q "$5"; then
    pass=$((pass + 1))
  else
    echo "FAIL $1: rc=$rc (期待 $4) / パターン=$5"
    fail=$((fail + 1))
  fi
}

mkdir -p "$BASE/hook-tmp"

# 1. git リポジトリ外 → 許可
dir="$BASE/plain"; mkdir -p "$dir"
check "non-git-cwd" 0 "$(run_gate "$dir" s01)"

# 2. git リポジトリ・conf なし → 許可
repo=$(make_repo r02)
touch "$repo/dirty.txt"
check "no-conf" 0 "$(run_gate "$repo" s02)"

# 3. conf がコメントと空行のみ → 許可
repo=$(make_repo r03)
mkdir -p "$repo/.claude"
printf '# comment only\n\n' >"$repo/.claude/stop-gate.conf"
check "empty-conf" 0 "$(run_gate "$repo" s03)"

# 4. 検証コマンド成功 (dirty tree) → 許可
repo=$(make_repo r04)
mkdir -p "$repo/.claude"
printf '# gate\ntrue\n' >"$repo/.claude/stop-gate.conf"
check "gate-pass" 0 "$(run_gate "$repo" s04)"

# 5. 検証コマンド失敗 (dirty tree) → ブロック
repo=$(make_repo r05)
mkdir -p "$repo/.claude"
printf 'false\n' >"$repo/.claude/stop-gate.conf"
check "gate-fail" 2 "$(run_gate "$repo" s05)"

# 6. 検証コマンド失敗だが tree が clean → 検証せず許可
repo=$(make_repo r06)
mkdir -p "$repo/.claude"
printf 'false\n' >"$repo/.claude/stop-gate.conf"
git -C "$repo" add -A
git -C "$repo" commit -qm init
check "clean-tree-skip" 0 "$(run_gate "$repo" s06)"

# 7. 連続ブロック cap: 3 回ブロック後の 4 回目は fail-open
repo=$(make_repo r07)
mkdir -p "$repo/.claude"
printf 'false\n' >"$repo/.claude/stop-gate.conf"
check "cap-block-1" 2 "$(run_gate "$repo" s07)"
check "cap-block-2" 2 "$(run_gate "$repo" s07)"
check "cap-block-3" 2 "$(run_gate "$repo" s07)"
check "cap-failopen-4" 0 "$(run_gate "$repo" s07)"
# cap 発動でカウンタが消えるので、次はまたブロックに戻る
check "cap-restart-5" 2 "$(run_gate "$repo" s07)"

# 8. pass でカウンタがリセットされる
repo=$(make_repo r08)
mkdir -p "$repo/.claude"
printf 'false\n' >"$repo/.claude/stop-gate.conf"
check "reset-block-1" 2 "$(run_gate "$repo" s08)"
check "reset-block-2" 2 "$(run_gate "$repo" s08)"
printf 'true\n' >"$repo/.claude/stop-gate.conf"
check "reset-pass" 0 "$(run_gate "$repo" s08)"
printf 'false\n' >"$repo/.claude/stop-gate.conf"
check "reset-block-again-1" 2 "$(run_gate "$repo" s08)"
check "reset-block-again-2" 2 "$(run_gate "$repo" s08)"
check "reset-block-again-3" 2 "$(run_gate "$repo" s08)"
check "reset-cap-4" 0 "$(run_gate "$repo" s08)"

# 9. 検証コマンドの失敗出力が stderr に含まれる (フィードバック契約)
repo=$(make_repo r09)
mkdir -p "$repo/.claude"
printf 'echo BOOM-MARKER; false\n' >"$repo/.claude/stop-gate.conf"
check_stderr_contains "stderr-feedback" "$repo" s09 2 "BOOM-MARKER"

# 10. JSON に cwd が無い場合は実行時 pwd にフォールバック
repo=$(make_repo r10)
mkdir -p "$repo/.claude"
printf 'false\n' >"$repo/.claude/stop-gate.conf"
touch "$repo/dirty.txt"
rc=0
printf '%s' '{"session_id":"s10","hook_event_name":"Stop","stop_hook_active":false}' \
  | (cd "$repo" && TMPDIR="$BASE/hook-tmp" bash "$HOOK" >/dev/null 2>&1) || rc=$?
check "cwd-fallback" 2 "$rc"

# T-1. tail -n 20 の境界: 30 行出力して fail するとき末尾 20 行 (line-30..line-11) が
#      stderr に載り、line-10 は載らない。ヘッダも確認
repo=$(make_repo r11)
mkdir -p "$repo/.claude"
printf 'i=1; while [ "$i" -le 30 ]; do printf "line-%%02d\\n" "$i"; i=$((i+1)); done; false\n' >"$repo/.claude/stop-gate.conf"
json=$(jq -cn --arg cwd "$repo" \
  '{"session_id":"s11","hook_event_name":"Stop","stop_hook_active":false,"cwd":$cwd}')
stderr_out=$(printf '%s' "$json" | TMPDIR="$BASE/hook-tmp" bash "$HOOK" 2>&1 >/dev/null) || true
if printf '%s' "$stderr_out" | grep -q "検証コマンドが失敗しました" \
  && printf '%s' "$stderr_out" | grep -q "line-30" \
  && printf '%s' "$stderr_out" | grep -q "line-11" \
  && ! printf '%s' "$stderr_out" | grep -q "line-10"; then
  pass=$((pass + 1))
else
  echo "FAIL tail-boundary: tail -n 20 の境界 or ヘッダが期待どおりでない"
  fail=$((fail + 1))
fi

# T-2. cap 発動 (4 回目) の stderr に「手動で確認してください」が含まれる
repo=$(make_repo r12)
mkdir -p "$repo/.claude"
printf 'false\n' >"$repo/.claude/stop-gate.conf"
run_gate "$repo" s12 >/dev/null
run_gate "$repo" s12 >/dev/null
run_gate "$repo" s12 >/dev/null
check_stderr_contains "cap-manual-message" "$repo" s12 0 "手動で確認してください"

# H-9. hook_event_name が Stop 以外 (PreToolUse) なら fail する conf + dirty tree でも許可
repo=$(make_repo r13)
mkdir -p "$repo/.claude"
printf 'false\n' >"$repo/.claude/stop-gate.conf"
rc=0
json=$(jq -cn --arg cwd "$repo" \
  '{"session_id":"s13","hook_event_name":"PreToolUse","stop_hook_active":false,"cwd":$cwd}')
printf '%s' "$json" | TMPDIR="$BASE/hook-tmp" bash "$HOOK" >/dev/null 2>&1 || rc=$?
check "non-stop-event" 0 "$rc"

# H-2. conf が unset var を素で参照しても hook の set -u で死なない (fresh bash -c)
repo=$(make_repo r14)
mkdir -p "$repo/.claude"
printf 'test -z "$STOP_GATE_TEST_UNSET_VAR_1234"\n' >"$repo/.claude/stop-gate.conf"
check "unset-var-no-inherit" 0 "$(run_gate "$repo" s14)"

# H-3. CRLF 行末の conf でもコマンドが正しく採用される
repo=$(make_repo r15)
mkdir -p "$repo/.claude"
printf 'true\r\n' >"$repo/.claude/stop-gate.conf"
check "crlf-conf" 0 "$(run_gate "$repo" s15)"

# H-1. session_id にパストラバーサルを渡しても unknown に落ち、counter は hook-tmp 内に作られる
repo=$(make_repo r16)
mkdir -p "$repo/.claude"
printf 'false\n' >"$repo/.claude/stop-gate.conf"
check "sid-traversal-block" 2 "$(run_gate "$repo" '../evil/x')"
if [ -f "$BASE/hook-tmp/stop-gate.unknown.count" ] && [ ! -e "$BASE/hook-tmp/../evil/x" ]; then
  pass=$((pass + 1))
else
  echo "FAIL sid-traversal-path: counter が hook-tmp/stop-gate.unknown.count に作られていない"
  fail=$((fail + 1))
fi

# H-5. タイムアウトでブロック: 孫プロセスが stdout を掴む最悪ケースでも group kill でパイプが
#      閉じてすぐブロックに落ち (旧 exec 方式なら bg の sleep 30 がパイプを握って ~30 秒 hang)、
#      stderr にタイムアウト注記が載る (run_gate は env を通さないので直接呼ぶ)
repo=$(make_repo r17)
mkdir -p "$repo/.claude"
printf 'sleep 30 & wait\n' >"$repo/.claude/stop-gate.conf"
rc=0
json=$(jq -cn --arg cwd "$repo" \
  '{"session_id":"s17","hook_event_name":"Stop","stop_hook_active":false,"cwd":$cwd}')
h5_start=$(date +%s)
stderr_out=$(printf '%s' "$json" | STOP_GATE_TIMEOUT_SECS=1 TMPDIR="$BASE/hook-tmp" bash "$HOOK" 2>&1 >/dev/null) || rc=$?
h5_elapsed=$(( $(date +%s) - h5_start ))
check "timeout-block" 2 "$rc"
if [ "$h5_elapsed" -lt 15 ] && printf '%s' "$stderr_out" | grep -q "タイムアウト"; then
  pass=$((pass + 1))
else
  echo "FAIL timeout-group-kill: elapsed=${h5_elapsed}s (15 秒未満 + stderr のタイムアウト注記を期待)"
  fail=$((fail + 1))
fi

# H-9b. malformed JSON (jq が失敗) → fail-open。fail conf + dirty tree でも許可
repo=$(make_repo r19)
mkdir -p "$repo/.claude"
printf 'false\n' >"$repo/.claude/stop-gate.conf"
rc=0
printf 'not json at all' | TMPDIR="$BASE/hook-tmp" bash "$HOOK" >/dev/null 2>&1 || rc=$?
check "malformed-json" 0 "$rc"

# H-9c. hook_event_name フィールド欠落 → fail-open (Stop 以外に落ちる)
repo=$(make_repo r20)
mkdir -p "$repo/.claude"
printf 'false\n' >"$repo/.claude/stop-gate.conf"
rc=0
json=$(jq -cn --arg cwd "$repo" '{"session_id":"s20","stop_hook_active":false,"cwd":$cwd}')
printf '%s' "$json" | TMPDIR="$BASE/hook-tmp" bash "$HOOK" >/dev/null 2>&1 || rc=$?
check "missing-event-field" 0 "$rc"

# H-7. 複数行 conf は先頭 1 行のみ採用 (2 行目以降は無視)
repo=$(make_repo r21)
mkdir -p "$repo/.claude"
printf 'true\necho SHOULD-NOT-RUN >&2; false\n' >"$repo/.claude/stop-gate.conf"
json=$(jq -cn --arg cwd "$repo" \
  '{"session_id":"s21","hook_event_name":"Stop","stop_hook_active":false,"cwd":$cwd}')
rc=0
stderr_out=$(printf '%s' "$json" | TMPDIR="$BASE/hook-tmp" bash "$HOOK" 2>&1 >/dev/null) || rc=$?
if [ "$rc" = 0 ] && ! printf '%s' "$stderr_out" | grep -q "SHOULD-NOT-RUN"; then
  pass=$((pass + 1))
else
  echo "FAIL multiline-conf-first-only: rc=$rc / stderr に 2 行目由来出力が混入"
  fail=$((fail + 1))
fi

# H-8. stdin が EOF (/dev/null) なら read -t 10 で待たず即 exit 0
h8_start=$(date +%s)
rc=0
TMPDIR="$BASE/hook-tmp" bash "$HOOK" </dev/null >/dev/null 2>&1 || rc=$?
h8_elapsed=$(( $(date +%s) - h8_start ))
if [ "$rc" = 0 ] && [ "$h8_elapsed" -lt 5 ]; then
  pass=$((pass + 1))
else
  echo "FAIL stdin-eof: rc=$rc elapsed=${h8_elapsed}s (即 exit 0 を期待)"
  fail=$((fail + 1))
fi

echo "----"
echo "stop-verify-gate tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
