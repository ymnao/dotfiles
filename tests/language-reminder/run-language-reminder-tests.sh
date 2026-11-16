#!/usr/bin/env bash
# Why not -e: hook の出力が空のケースを期待値として受けるため、失敗で止めない
set -uo pipefail

# language-reminder.sh のシナリオテスト (#507)。
# UserPromptSubmit / PostToolUse の payload を流し、stdout の JSON を見る。
#
# 使い方: run-language-reminder-tests.sh
#   環境変数 HOOK_PATH で hook の場所を上書きできる
#
# 依存: bash 3.2+ / jq / git

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
HOOK="${HOOK_PATH:-$REPO_ROOT/claude/hooks/language-reminder.sh}"

if [ ! -f "$HOOK" ]; then
  echo "ERROR: hook not found: $HOOK (HOOK_PATH で上書き可)" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/language-reminder-tests.XXXXXX")"
trap 'rm -rf "$T"' EXIT

pass=0
fail=0
# 独立した定数として持つ (ケース定義から導出しない)
EXPECTED_CASES=12

mkdir -p "$T/cfg" "$T/nolang" "$T/tmp"
printf '%s\n' '{"language": "japanese"}' > "$T/cfg/settings.json"
printf '%s\n' '{"model": "x"}' > "$T/nolang/settings.json"

# fire <event> [session] [config-dir] — hook の stdout を返す
fire() {
  jq -cn --arg e "$1" --arg s "${2-s1}" '{hook_event_name:$e, session_id:$s}' \
    | CLAUDE_CONFIG_DIR="${3-$T/cfg}" TMPDIR="$T/tmp" bash "$HOOK" 2>/dev/null
}

check() {
  local name="$1"
  shift
  if "$@"; then
    pass=$((pass + 1))
  else
    echo "FAIL $name"
    fail=$((fail + 1))
  fi
}

emits_for() {
  printf '%s' "$2" | jq -e --arg e "$1" \
    '.hookSpecificOutput.hookEventName == $e and (.hookSpecificOutput.additionalContext | test("japanese"))' >/dev/null 2>&1
}

out=$(fire UserPromptSubmit)
check "prompt-emits" emits_for UserPromptSubmit "$out"
check "prompt-stdout-is-single-json" test "$(printf '%s' "$out" | jq -s 'length' 2>/dev/null)" = 1

# 1〜9 回目は出ず、10 回目だけ出る
silent=0
for _ in 1 2 3 4 5 6 7 8 9; do
  [ -z "$(fire PostToolUse)" ] && silent=$((silent + 1))
done
check "tool-1-to-9-silent" test "$silent" = 9
check "tool-10-emits" emits_for PostToolUse "$(fire PostToolUse)"
check "tool-11-silent" test -z "$(fire PostToolUse)"

# プロンプトでカウンタが戻る: 5 回進めてからプロンプト → 次の 10 回目まで出ない
for _ in 1 2 3 4 5; do fire PostToolUse >/dev/null; done
fire UserPromptSubmit >/dev/null
silent=0
for _ in 1 2 3 4 5 6 7 8 9; do
  [ -z "$(fire PostToolUse)" ] && silent=$((silent + 1))
done
check "reset-by-prompt-silent-until-10" test "$silent" = 9
check "reset-by-prompt-emits-at-10" emits_for PostToolUse "$(fire PostToolUse)"

# カウンタはセッションごとに別
for _ in 1 2 3 4 5 6 7 8 9; do fire PostToolUse s2 >/dev/null; done
check "other-session-independent" test -z "$(fire PostToolUse s3)"

# session_id のパス区切りはサニタイズされ、カウンタは TMPDIR の外に出ない
fire UserPromptSubmit "../../escape" >/dev/null
check "session-id-sanitized" test ! -e "$T/escape"

check "no-language-prompt-silent" test -z "$(fire UserPromptSubmit s1 "$T/nolang")"
check "missing-settings-silent" test -z "$(fire UserPromptSubmit s1 "$T/none")"
check "other-event-silent" test -z "$(fire Stop)"

total=$((pass + fail))
echo "language-reminder: $pass passed, $fail failed ($total run)"
if [ "$total" -ne "$EXPECTED_CASES" ]; then
  echo "FAIL: 実行ケース数 $total が期待値 $EXPECTED_CASES と一致しない"
  exit 1
fi
[ "$fail" -eq 0 ]
