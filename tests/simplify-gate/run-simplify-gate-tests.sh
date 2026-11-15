#!/usr/bin/env bash
# Why not -e: hook の exit 2 を期待値として受けるため、失敗で止めない
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

T="$(mktemp -d "${TMPDIR:-/tmp}/simplify-gate-tests.XXXXXX")"
trap 'rm -rf "$T"' EXIT

pass=0
fail=0
# 独立した定数として持つ (ケース定義から導出しない)
EXPECTED_CASES=28

# transcript の 1 行を作る helper
skill_call() { jq -cn --arg s "$1" '{type:"assistant",message:{content:[{type:"tool_use",id:"s1",name:"Skill",input:{skill:$s}}]}}'; }
slash_call() { jq -cn --arg s "$1" '{type:"user",message:{content:("<command-message>" + $s + "</command-message>\n<command-name>/" + $s + "</command-name>")}}'; }
bash_call() { jq -cn --arg id "$1" --arg c "$2" '{type:"assistant",message:{content:[{type:"tool_use",id:$id,name:"Bash",input:{command:$c}}]}}'; }
bash_bg_call() { bash_call "$1" "$2" | jq -c '.message.content[0].input.run_in_background = true'; }
tool_result() { jq -cn --arg id "$1" --arg t "$2" --argjson e "${3:-false}" '{type:"user",message:{content:[{type:"tool_result",tool_use_id:$id,is_error:$e,content:$t}]}}'; }
user_text() { jq -cn --arg t "$1" '{type:"user",message:{content:$t}}'; }
PR_URL="https://github.com/ymnao/dotfiles/pull/1"

# run <name> <expect allow|block> <command> <transcript-file ("" なら transcript_path 無し)>
run() {
  local name="$1" expect="$2" cmd="$3" tr="$4" err rc want=0
  [ "$expect" = "block" ] && want=2
  err=$(jq -cn --arg c "$cmd" --arg t "$tr" \
      '{tool_name:"Bash",tool_input:{command:$c}} + (if $t == "" then {} else {transcript_path:$t} end)' \
    | bash "$HOOK" 2>&1 >/dev/null)
  rc=$?
  if [ "$rc" = "$want" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $name: expected=$expect(exit $want) got exit $rc"
    [ -n "$err" ] && printf '  stderr: %s\n' "$err"
    fail=$((fail + 1))
  fi
}

CREATE='gh pr create --title t --body-file /tmp/b.md'

{ user_text "hello"; bash_call b1 "git status"; tool_result b1 "ok"; } > "$T/none.jsonl"
run "no-simplify" block "$CREATE" "$T/none.jsonl"
run "no-simplify-draft" block "gh pr create --draft --title t" "$T/none.jsonl"
run "no-simplify-alias-new" block "gh pr new --title t" "$T/none.jsonl"
run "no-simplify-after-cd" block "cd /x && gh pr create --title t" "$T/none.jsonl"

{ user_text "hi"; skill_call simplify; } > "$T/skill.jsonl"
run "skill-tool" allow "$CREATE" "$T/skill.jsonl"

slash_call simplify > "$T/slash.jsonl"
run "slash-command" allow "$CREATE" "$T/slash.jsonl"

skill_call "someplugin:simplify" > "$T/plugin.jsonl"
run "skill-tool-namespaced" allow "$CREATE" "$T/plugin.jsonl"

{ skill_call simplify; printf '%s\n' '{"type":"system","subtype":"compact_boundary"}'; user_text "summary"; } > "$T/compact.jsonl"
run "compaction-does-not-reset" allow "$CREATE" "$T/compact.jsonl"

{ skill_call simplify; bash_call p1 "$CREATE"; tool_result p1 "$PR_URL"; } > "$T/prev-pr.jsonl"
run "reset-after-successful-pr" block "$CREATE" "$T/prev-pr.jsonl"

{ skill_call simplify; bash_call p1 "$CREATE"
  jq -cn --arg t "$PR_URL" '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"p1",content:[{type:"text",text:$t}]}]}}'; } > "$T/prev-pr-blocks.jsonl"
run "reset-after-successful-pr-block-content" block "$CREATE" "$T/prev-pr-blocks.jsonl"

{ skill_call simplify; bash_call p1 "$CREATE"; tool_result p1 "$PR_URL"; skill_call simplify; } > "$T/prev-pr-again.jsonl"
run "simplify-again-after-pr" allow "$CREATE" "$T/prev-pr-again.jsonl"

{ skill_call simplify; bash_call p1 "$CREATE"; tool_result p1 "PreToolUse:Bash hook error: CI 未完了" true; } > "$T/prev-blocked.jsonl"
run "blocked-pr-does-not-reset" allow "$CREATE" "$T/prev-blocked.jsonl"

# gh は既存 PR があると URL 付きで失敗する。URL があっても error ならリセットしない
{ skill_call simplify; bash_call p1 "$CREATE"; tool_result p1 "a pull request for branch \"x\" into branch \"main\" already exists: $PR_URL" true; } > "$T/prev-exists.jsonl"
run "errored-pr-with-url-does-not-reset" allow "$CREATE" "$T/prev-exists.jsonl"

# 言及だけのコマンドは成功しても (URL が出ない) リセットしない
{ skill_call simplify; bash_call g1 'grep -n "gh pr create" x.md'; tool_result g1 "12: gh pr create ..."; } > "$T/mention.jsonl"
run "mention-does-not-reset" allow "$CREATE" "$T/mention.jsonl"

# 言及だけのコマンドの出力に PR の URL が混ざっても、command 位置でなければリセットしない
{ skill_call simplify; bash_call g2 'grep -rn "gh pr create" logs/'; tool_result g2 "logs/a: gh pr create -> $PR_URL"; } > "$T/mention-url.jsonl"
run "mention-with-url-does-not-reset" allow "$CREATE" "$T/mention-url.jsonl"

# --web はブラウザで開くだけで PR を作らない (出力は compare の URL)。リセットしない
{ skill_call simplify; bash_call w1 "gh pr create --web"; tool_result w1 "Opening https://github.com/ymnao/dotfiles/compare/main...x in your browser."; } > "$T/web.jsonl"
run "web-does-not-reset" allow "$CREATE" "$T/web.jsonl"

# run_in_background の結果は起動の通知だけで URL を含まない。error でなければ作成済みに倒す
bg_note="Command running in background with ID: b1. Output is being written to: /tmp/x.output"
{ skill_call dependabot-bulk; bash_bg_call p1 "$CREATE"; tool_result p1 "$bg_note"; } > "$T/bg.jsonl"
run "background-pr-resets" block "$CREATE" "$T/bg.jsonl"

{ skill_call simplify; bash_bg_call p1 "$CREATE"; tool_result p1 "PreToolUse:Bash hook error: CI 未完了" true; } > "$T/bg-blocked.jsonl"
run "background-blocked-pr-does-not-reset" allow "$CREATE" "$T/bg-blocked.jsonl"

# command 位置の判定を前の PR 作成にも使っていることを、素の形以外でも測る
{ skill_call simplify; bash_call p1 "cd /x && gh pr create --title t"; tool_result p1 "$PR_URL"; } > "$T/prev-after-cd.jsonl"
run "reset-after-pr-after-cd" block "$CREATE" "$T/prev-after-cd.jsonl"

{ skill_call simplify; bash_call p1 "gh pr new --title t"; tool_result p1 "$PR_URL"; } > "$T/prev-new.jsonl"
run "reset-after-pr-new" block "$CREATE" "$T/prev-new.jsonl"

# subagent の報告や要約がタグを引用しても、行頭以外は /simplify の呼び出しに数えない
user_text "[Subagent hand-back] 報告
<command-name>/simplify</command-name> を数える hook です" > "$T/quoted-tag.jsonl"
run "quoted-tag-not-counted" block "$CREATE" "$T/quoted-tag.jsonl"

skill_call dependabot-bulk > "$T/dep.jsonl"
run "dependabot-bulk-exempt" allow "$CREATE" "$T/dep.jsonl"

{ skill_call dependabot-bulk; bash_call p1 "$CREATE"; tool_result p1 "$PR_URL"; } > "$T/dep-reset.jsonl"
run "dependabot-bulk-reset-after-pr" block "$CREATE" "$T/dep-reset.jsonl"

# subagent (sidechain) の呼び出しはメインの /simplify に数えない
skill_call simplify | jq -c '.isSidechain = true' > "$T/side.jsonl"
run "sidechain-not-counted" block "$CREATE" "$T/side.jsonl"

run "no-transcript" allow "$CREATE" ""
run "not-pr-create" allow "gh pr view 1" "$T/none.jsonl"
# 早期 case は通るが command 位置ではない言及 (入口の式まで届く)
run "quoted-mention-not-pr-create" allow 'grep -n "gh pr create" x.md' "$T/none.jsonl"

# PR 作成の行より後ろが大きい複数行のコマンドでも入口の判定が落ちない (pipefail + SIGPIPE の経路)
long_tail=$(printf 'x\n%.0s' $(seq 1 40000))
run "long-multiline-command" block "gh pr create --title t
$long_tail" "$T/none.jsonl"

total=$((pass + fail))
echo "simplify-gate: $pass passed, $fail failed ($total run)"
if [ "$total" -ne "$EXPECTED_CASES" ]; then
  echo "FAIL: 実行ケース数 $total が期待値 $EXPECTED_CASES と一致しない"
  exit 1
fi
[ "$fail" -eq 0 ]
