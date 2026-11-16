#!/usr/bin/env bash
# Why not -e: hook の出力が空のケースを期待値として受けるため、失敗で止めない
set -uo pipefail

# language-reminder.sh のシナリオテスト (#507)。
# UserPromptSubmit / PostToolUse の payload を流し、stdout の JSON と exit code を見る。
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

T="$(mktemp -d "${TMPDIR:-/tmp}/language-reminder-tests.XXXXXX")" || { echo "ERROR: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT

pass=0
fail=0
# 独立した定数として持つ (ケース定義から導出しない)
EXPECTED_CASES=22

mkdir -p "$T/cfg" "$T/nolang" "$T/broken" "$T/en" "$T/home/.claude" "$T/tmp" "$T/filetmp" "$T/linktmp" "$T/elsewhere" || exit 1
printf '%s\n' '{"language": "japanese"}' > "$T/cfg/settings.json"
printf '%s\n' '{"model": "x"}' > "$T/nolang/settings.json"
printf '%s\n' '{"language": ' > "$T/broken/settings.json"
printf '%s\n' '{"language": "english"}' > "$T/en/settings.json"
printf '%s\n' '{"language": "home-fallback"}' > "$T/home/.claude/settings.json"
COUNTERS="$T/tmp/claude-language-reminder-$(id -u)"

# fire <event> [session] [config-dir] — hook の stdout を返す。exit が 0 以外なら末尾に EXIT=<n> を足す
fire() {
  local out rc
  out=$(jq -cn --arg e "$1" --arg s "${2-s1}" '{hook_event_name:$e, session_id:$s}' \
    | CLAUDE_CONFIG_DIR="${3-$T/cfg}" TMPDIR="$T/tmp" bash "$HOOK" 2>/dev/null)
  rc=$?
  printf '%s' "$out"
  [ "$rc" -eq 0 ] || printf 'EXIT=%s' "$rc"
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

# emits_for <event> <stdout> [言語の値]
emits_for() {
  printf '%s' "$2" | jq -e --arg e "$1" --arg l "${3:-japanese}" \
    '.hookSpecificOutput.hookEventName == $e and (.hookSpecificOutput.additionalContext | contains("(" + $l + ")"))' >/dev/null 2>&1
}

# PostToolUse を 9 回流し、何も出さず exit 0 だった回数を返す
silent_9() {
  local n=0
  for _ in 1 2 3 4 5 6 7 8 9; do
    [ -z "$(fire PostToolUse "$@")" ] && n=$((n + 1))
  done
  echo "$n"
}

out=$(fire UserPromptSubmit)
check "prompt-emits" emits_for UserPromptSubmit "$out"
check "prompt-stdout-is-single-json" test "$(printf '%s' "$out" | jq -s 'length' 2>/dev/null)" = 1

# 1〜9 回目は出ず、10 回目だけ出る。倍数ごとなので 20 回目も出る
check "tool-1-to-9-silent" test "$(silent_9)" = 9
check "tool-10-emits" emits_for PostToolUse "$(fire PostToolUse)"
check "tool-11-to-19-silent" test "$(silent_9)" = 9
check "tool-20-emits" emits_for PostToolUse "$(fire PostToolUse)"

# プロンプトでカウンタが戻る: 5 回進めてからプロンプト → 次の 10 回目まで出ない
for _ in 1 2 3 4 5; do fire PostToolUse >/dev/null; done
fire UserPromptSubmit >/dev/null
check "reset-by-prompt-silent-until-10" test "$(silent_9)" = 9
check "reset-by-prompt-emits-at-10" emits_for PostToolUse "$(fire PostToolUse)"

# カウンタはセッションごとに別
silent_9 s2 >/dev/null
check "other-session-independent" test -z "$(fire PostToolUse s3)"

# カウンタの値: 先頭ゼロは 10 進で読み、数値でなければ 0 から数え直す
printf '000000009\n' > "$COUNTERS/s4"
out=$(fire PostToolUse s4)
check "counter-leading-zero-decimal" test "$(cat "$COUNTERS/s4")" = 10 -a -n "$out"
printf 'abc\n' > "$COUNTERS/s5"
check "counter-garbage-restarts" test -z "$(fire PostToolUse s5)"

# session_id のパス区切りはサニタイズされ、カウンタはカウンタ置き場の外に出ない
fire UserPromptSubmit "../../escape" >/dev/null
check "session-id-sanitized" test ! -e "$T/escape"

check "language-value-passed-through" emits_for UserPromptSubmit "$(fire UserPromptSubmit s1 "$T/en")" english
check "no-language-prompt-silent" test -z "$(fire UserPromptSubmit s1 "$T/nolang")"
check "missing-settings-silent" test -z "$(fire UserPromptSubmit s1 "$T/none")"
check "broken-settings-silent" test -z "$(fire UserPromptSubmit s1 "$T/broken")"
check "other-event-silent" test -z "$(fire Stop)"

# CLAUDE_CONFIG_DIR が無ければ $HOME/.claude の settings を読む
out=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"h"}' \
  | env -u CLAUDE_CONFIG_DIR HOME="$T/home" TMPDIR="$T/tmp" bash "$HOOK" 2>/dev/null)
check "home-config-fallback" emits_for UserPromptSubmit "$out" home-fallback

# jq が無い / 壊れた入力: 何も出さず exit 0
out=$(printf '%s' '{"hook_event_name":"UserPromptSubmit"}' | PATH="$T/elsewhere" TMPDIR="$T/tmp" "$BASH" "$HOOK" 2>&1; printf 'EXIT=%s' "$?")
check "no-jq-silent" test "$out" = "EXIT=0"
out=$(printf '%s' 'not json' | CLAUDE_CONFIG_DIR="$T/cfg" TMPDIR="$T/tmp" bash "$HOOK" 2>&1; printf 'EXIT=%s' "$?")
check "broken-input-silent" test "$out" = "EXIT=0"

# カウンタ置き場が作れない (同名のファイルがある) / symlink のときは書かずに通す
: > "$T/filetmp/claude-language-reminder-$(id -u)"
out=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"f"}' \
  | CLAUDE_CONFIG_DIR="$T/cfg" TMPDIR="$T/filetmp" bash "$HOOK" 2>&1; printf 'EXIT=%s' "$?")
check "counter-dir-unavailable-silent" test "$out" = "EXIT=0"
ln -s "$T/elsewhere" "$T/linktmp/claude-language-reminder-$(id -u)"
out=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"l"}' \
  | CLAUDE_CONFIG_DIR="$T/cfg" TMPDIR="$T/linktmp" bash "$HOOK" 2>&1; printf 'EXIT=%s' "$?")
check "counter-dir-symlink-rejected" test "$out" = "EXIT=0" -a ! -e "$T/elsewhere/l"

total=$((pass + fail))
echo "language-reminder: $pass passed, $fail failed ($total run)"
if [ "$total" -ne "$EXPECTED_CASES" ]; then
  echo "FAIL: 実行ケース数 $total が期待値 $EXPECTED_CASES と一致しない"
  exit 1
fi
[ "$fail" -eq 0 ]
