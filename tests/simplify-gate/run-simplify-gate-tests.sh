#!/usr/bin/env bash
set -uo pipefail

# require-simplify-before-pr.sh のシナリオテスト (#508)。
# transcript の fixture を作り、gh pr create の payload を流して exit code を見る。
#
# 使い方: run-simplify-gate-tests.sh
#   環境変数 HOOK_PATH で hook の場所を上書きできる
#
# 依存: bash 3.2+ / jq / git

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
HOOK="${HOOK_PATH:-$REPO_ROOT/claude/hooks/require-simplify-before-pr.sh}"

if [ ! -f "$HOOK" ]; then
  echo "ERROR: hook not found: $HOOK (HOOK_PATH で上書き可)" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }

BASE="$(mktemp -d "${TMPDIR:-/tmp}/simplify-gate-tests.XXXXXX")"
cleanup() { [ -n "${BASE:-}" ] && rm -rf "$BASE"; }
trap cleanup EXIT

pass=0
fail=0
# 独立した定数として持つ (ケース定義から導出しない)
EXPECTED_CASES=19

# transcript の 1 行を作る helper
skill_call() { jq -cn --arg s "$1" '{type:"assistant",message:{content:[{type:"tool_use",id:"s1",name:"Skill",input:{skill:$s}}]}}'; }
slash_call() { jq -cn --arg s "$1" '{type:"user",message:{content:("<command-message>" + $s + "</command-message>\n<command-name>/" + $s + "</command-name>")}}'; }
bash_call() { jq -cn --arg id "$1" --arg c "$2" '{type:"assistant",message:{content:[{type:"tool_use",id:$id,name:"Bash",input:{command:$c}}]}}'; }
tool_result() { jq -cn --arg id "$1" --arg t "$2" --argjson e "$3" '{type:"user",message:{content:[{type:"tool_result",tool_use_id:$id,is_error:$e,content:$t}]}}'; }
tool_result_blocks() { jq -cn --arg id "$1" --arg t "$2" '{type:"user",message:{content:[{type:"tool_result",tool_use_id:$id,content:[{type:"text",text:$t}]}]}}'; }
compact() { printf '%s\n' '{"type":"system","subtype":"compact_boundary"}'; }
user_text() { jq -cn --arg t "$1" '{type:"user",message:{content:$t}}'; }
PR_URL="https://github.com/ymnao/dotfiles/pull/1"

# run <name> <expect allow|block> <command> <transcript-file|-none->
run() {
  local name="$1" expect="$2" cmd="$3" tr="$4" payload rc want
  if [ "$tr" = "-none-" ]; then
    payload=$(jq -cn --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
  else
    payload=$(jq -cn --arg c "$cmd" --arg t "$tr" '{tool_name:"Bash",tool_input:{command:$c},transcript_path:$t}')
  fi
  printf '%s' "$payload" | bash "$HOOK" >/dev/null 2>"$BASE/stderr"
  rc=$?
  want=0
  [ "$expect" = "block" ] && want=2
  if [ "$rc" = "$want" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $name: expected=$expect(exit $want) got exit $rc"
    sed 's/^/  stderr: /' "$BASE/stderr"
    fail=$((fail + 1))
  fi
}

T="$BASE/t"
mkdir -p "$T"
CREATE='gh pr create --title t --body-file /tmp/b.md'

{ user_text "hello"; bash_call b1 "git status"; tool_result b1 "ok" false; } > "$T/none.jsonl"
run "no-simplify" block "$CREATE" "$T/none.jsonl"
run "no-simplify-draft" block "gh pr create --draft --title t" "$T/none.jsonl"
run "no-simplify-alias-new" block "gh pr new --title t" "$T/none.jsonl"
run "no-simplify-after-cd" block "cd /x && gh pr create --title t" "$T/none.jsonl"

{ user_text "hi"; skill_call simplify; } > "$T/skill.jsonl"
run "skill-tool" allow "$CREATE" "$T/skill.jsonl"

{ slash_call simplify; } > "$T/slash.jsonl"
run "slash-command" allow "$CREATE" "$T/slash.jsonl"

{ skill_call "someplugin:simplify"; } > "$T/plugin.jsonl"
run "skill-tool-namespaced" allow "$CREATE" "$T/plugin.jsonl"

{ skill_call simplify; compact; user_text "summary"; } > "$T/compact.jsonl"
run "compaction-does-not-reset" allow "$CREATE" "$T/compact.jsonl"

{ skill_call simplify; bash_call p1 "$CREATE"; tool_result p1 "$PR_URL" false; } > "$T/prev-pr.jsonl"
run "reset-after-successful-pr" block "$CREATE" "$T/prev-pr.jsonl"

{ skill_call simplify; bash_call p1 "$CREATE"; tool_result_blocks p1 "$PR_URL"; } > "$T/prev-pr-blocks.jsonl"
run "reset-after-successful-pr-block-content" block "$CREATE" "$T/prev-pr-blocks.jsonl"

{ skill_call simplify; bash_call p1 "$CREATE"; tool_result p1 "$PR_URL" false; skill_call simplify; } > "$T/prev-pr-again.jsonl"
run "simplify-again-after-pr" allow "$CREATE" "$T/prev-pr-again.jsonl"

{ skill_call simplify; bash_call p1 "$CREATE"; tool_result p1 "PreToolUse:Bash hook error: CI 未完了" true; } > "$T/prev-blocked.jsonl"
run "blocked-pr-does-not-reset" allow "$CREATE" "$T/prev-blocked.jsonl"

# gh は既存 PR があると URL 付きで失敗する。URL があっても error ならリセットしない
{ skill_call simplify; bash_call p1 "$CREATE"; tool_result p1 "a pull request for branch \"x\" into branch \"main\" already exists: $PR_URL" true; } > "$T/prev-exists.jsonl"
run "errored-pr-with-url-does-not-reset" allow "$CREATE" "$T/prev-exists.jsonl"

# 言及だけのコマンドが成功しても (URL が出ない) リセットしない
{ skill_call simplify; bash_call g1 'grep -n "gh pr create" x.md'; tool_result g1 "12: gh pr create ..." false; } > "$T/mention.jsonl"
run "mention-does-not-reset" allow "$CREATE" "$T/mention.jsonl"

{ skill_call dependabot-bulk; } > "$T/dep.jsonl"
run "dependabot-bulk-exempt" allow "$CREATE" "$T/dep.jsonl"

{ skill_call dependabot-bulk; bash_call p1 "$CREATE"; tool_result p1 "$PR_URL" false; } > "$T/dep-reset.jsonl"
run "dependabot-bulk-reset-after-pr" block "$CREATE" "$T/dep-reset.jsonl"

# subagent (sidechain) の呼び出しはメインの /simplify に数えない
jq -cn '{type:"assistant",isSidechain:true,message:{content:[{type:"tool_use",id:"s1",name:"Skill",input:{skill:"simplify"}}]}}' > "$T/side.jsonl"
run "sidechain-not-counted" block "$CREATE" "$T/side.jsonl"

run "no-transcript" allow "$CREATE" "-none-"
run "not-pr-create" allow "gh pr view 1" "$T/none.jsonl"

total=$((pass + fail))
echo "simplify-gate: $pass passed, $fail failed ($total run)"
if [ "$total" -ne "$EXPECTED_CASES" ]; then
  echo "FAIL: 実行ケース数 $total が期待値 $EXPECTED_CASES と一致しない"
  exit 1
fi
[ "$fail" -eq 0 ]
