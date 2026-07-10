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
json=$(jq -cn --arg cwd "$repo" \
  '{"session_id":"s09","hook_event_name":"Stop","stop_hook_active":false,"cwd":$cwd}')
stderr_out=$(printf '%s' "$json" | TMPDIR="$BASE/hook-tmp" bash "$HOOK" 2>&1 >/dev/null) || true
if printf '%s' "$stderr_out" | grep -q "BOOM-MARKER"; then
  pass=$((pass + 1))
else
  echo "FAIL stderr-feedback: 失敗出力が stderr に含まれない"
  fail=$((fail + 1))
fi

# 9b. session_id にパス文字が含まれてもカウンタが機能する
#     (未サニタイズだと count ファイルの書き込みが失敗し cap が永久に発動しない)
repo=$(make_repo r09b)
mkdir -p "$repo/.claude"
printf 'false\n' >"$repo/.claude/stop-gate.conf"
check "sanitize-block-1" 2 "$(run_gate "$repo" '../evil')"
check "sanitize-block-2" 2 "$(run_gate "$repo" '../evil')"
check "sanitize-block-3" 2 "$(run_gate "$repo" '../evil')"
check "sanitize-cap-4" 0 "$(run_gate "$repo" '../evil')"
# カウンタが hook-tmp の外 (パストラバーサル先) に書かれていないこと
if [ -e "$BASE/evil.count" ]; then
  echo "FAIL sanitize-containment: カウンタが TMPDIR 外に書かれた"
  fail=$((fail + 1))
else
  pass=$((pass + 1))
fi

# 10. JSON に cwd が無い場合は実行時 pwd にフォールバック
repo=$(make_repo r10)
mkdir -p "$repo/.claude"
printf 'false\n' >"$repo/.claude/stop-gate.conf"
touch "$repo/dirty.txt"
rc=0
printf '%s' '{"session_id":"s10","hook_event_name":"Stop","stop_hook_active":false}' \
  | (cd "$repo" && TMPDIR="$BASE/hook-tmp" bash "$HOOK" >/dev/null 2>&1) || rc=$?
check "cwd-fallback" 2 "$rc"

echo "----"
echo "stop-verify-gate tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
