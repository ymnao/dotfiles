#!/usr/bin/env bash
set -uo pipefail

# session-compact-context.sh のシナリオテスト。
#
# 使い方: run-session-compact-tests.sh
#   環境変数 HOOK_PATH で hook の場所を上書きできる
#   (デフォルト: <リポジトリルート>/claude/hooks/session-compact-context.sh)
#
# 依存: bash 3.2+ / jq / git

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
HOOK="${HOOK_PATH:-$REPO_ROOT/claude/hooks/session-compact-context.sh}"

if [ ! -f "$HOOK" ]; then
  echo "ERROR: hook not found: $HOOK (HOOK_PATH で上書き可)" >&2
  exit 1
fi
for tool in jq git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool is required" >&2; exit 1; }
done

BASE="$(mktemp -d "${TMPDIR:-/tmp}/session-compact-tests.XXXXXX")"
cleanup() { [ -n "${BASE:-}" ] && rm -rf "$BASE"; }
trap cleanup EXIT

pass=0
fail=0

# 期待実行ケース数は**独立した定数**として持つ (ケース定義から導出しない。
# 導出するとケースが消えたとき下限も一緒に下がって検出が無効化される)。
EXPECTED_CASES=8

check() {
  if [ "$3" = "$2" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $1: expected=$2 got=$3"
    fail=$((fail + 1))
  fi
}

# テスト用リポジトリ
repo="$BASE/repo"
mkdir -p "$repo"
git -C "$repo" init -q
# auto gc / maintenance が detach 起動すると、trap の rm -rf と競合して
# 全ケース pass でもスイートが exit 1 になる (claude/rules/shell.md)
git -C "$repo" config gc.auto 0
git -C "$repo" config maintenance.auto false
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config user.name "test"
printf 'x\n' >"$repo/f.txt"
git -C "$repo" add -A
git -C "$repo" commit -qm "feat: 初期コミット"
git -C "$repo" checkout -qb feature/compact-test
printf 'y\n' >"$repo/dirty.txt"

json=$(jq -cn --arg cwd "$repo" \
  '{"session_id":"s1","hook_event_name":"SessionStart","source":"compact","cwd":$cwd}')

# 1. git リポジトリ内: exit 0 で、ブランチ名・変更件数・直近コミットを含む出力
out=$(printf '%s' "$json" | bash "$HOOK" 2>/dev/null)
rc=$?
check "exit-code" 0 "$rc"
printf '%s' "$out" | grep -q "feature/compact-test" && pass=$((pass + 1)) \
  || { echo "FAIL branch-name: 出力にブランチ名がない"; fail=$((fail + 1)); }
printf '%s' "$out" | grep -q "未コミット変更: 1 件" && pass=$((pass + 1)) \
  || { echo "FAIL dirty-count: 未コミット件数がない"; fail=$((fail + 1)); }
printf '%s' "$out" | grep -q "初期コミット" && pass=$((pass + 1)) \
  || { echo "FAIL recent-commits: 直近コミットがない"; fail=$((fail + 1)); }

# stdout の先頭行が `[` / `{` で始まってはいけない (issue #240)。codex はその 2 文字で
# 始まる stdout を JSON 出力とみなし、パースに失敗した時点で本文を model の context に
# 入れない。検査は **先頭行の全文 pin** で行う: 「1 文字目が `[` でない」だけを見る形は、
# 先頭に空行が入る mutant を素通しする (issue #215 で実際に踏んだ)。
# $out は上で 2>/dev/null (stdout 単独) で取得済み — 2>&1 で取ると stderr の 1 行が
# 混じって pin が壊れる。横断の静的検査は scripts/lint-hook-stdout.sh 側。
first_line=${out%%$'\n'*}
check "stdout-first-line" "session-compact-context: コンパクション後の作業状態リマインダー" "$first_line"

# 2. git リポジトリ外: 出力なし・exit 0
plain="$BASE/plain"; mkdir -p "$plain"
json2=$(jq -cn --arg cwd "$plain" '{"hook_event_name":"SessionStart","source":"compact","cwd":$cwd}')
out2=$(printf '%s' "$json2" | bash "$HOOK" 2>/dev/null)
rc2=$?
check "non-git-exit" 0 "$rc2"
[ -z "$out2" ] && pass=$((pass + 1)) \
  || { echo "FAIL non-git-silent: リポジトリ外で出力がある"; fail=$((fail + 1)); }

# 3. cwd 無し JSON: 実行時 pwd にフォールバック (リポジトリ内から実行)
out3=$(printf '%s' '{"hook_event_name":"SessionStart","source":"compact"}' \
  | (cd "$repo" && bash "$HOOK" 2>/dev/null))
printf '%s' "$out3" | grep -q "feature/compact-test" && pass=$((pass + 1)) \
  || { echo "FAIL cwd-fallback: pwd フォールバックで出力が出ない"; fail=$((fail + 1)); }

echo "----"
echo "session-compact tests: $pass passed, $fail failed"
# 数えるのは pass ではなく実行数 (pass + fail)。pass を見ると「実行されたが FAIL した」を
# 「実行されていない」と誤って報告する。
if [ "$((pass + fail))" != "$EXPECTED_CASES" ]; then
  echo "FAIL case-count: expected ${EXPECTED_CASES} cases, ran $((pass + fail)) (ケースの取りこぼし)"
  exit 1
fi
[ "$fail" = 0 ] || exit 1
exit 0
