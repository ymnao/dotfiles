#!/usr/bin/env bash
#
# PreToolUse hook (Claude Code 専用): `gh pr create` (alias `gh pr new` 含む) の前に、
# このセッションで /simplify が呼ばれているかを transcript から判定し、無ければ止める (#508)
#
# - 数える範囲: 直前に成功した `gh pr create` より後 (PR 単位)。compaction ではリセットしない
#   (/simplify の効果は適用済みの修正としてコードに残るため、やり直させても得るものが無い)
# - 呼び出しの形: Skill tool の tool_use (agent が呼んだ) と <command-name> タグ (user が打った)
# - 免除: 同じ範囲で dependabot-bulk skill が呼ばれている (Dependabot 由来の統合 PR)
# - --draft は免除しない (CI 待ちの bypass とは目的が違い、draft も後で ready になる)
# - transcript が無い・読めない・jq が無いときは判定できないので通す
# - exit 0 = 許可, exit 2 = block (stderr が Claude にフィードバックされる)

set -uo pipefail

input=$(cat)

case "$input" in
  *gh*pr*create*|*gh*pr*new*) ;;
  *) exit 0 ;;
esac

command -v jq &>/dev/null || exit 0

command=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$command" ]] && exit 0

# command 位置の判定は verify-ci-before-pr.sh と同じ式に揃える
if ! printf '%s\n' "$command" \
  | grep -qE '(^|[;&|({`[:space:]/\])([A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*[[:space:]]+)*gh[[:space:]]+pr[[:space:]]+(create|new)'; then
  exit 0
fi

transcript=$(printf '%s\n' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
[[ -n "$transcript" && -f "$transcript" && -r "$transcript" ]] || exit 0

# 前の PR 作成の成否は tool_result の本文に PR の URL があるかで見る。is_error だけだと
# `grep "gh pr create"` のような言及だけのコマンドの成功もリセットに数えてしまう
# Why not `fromjson?` を外す: 書き込み途中の末尾行や壊れた行で全体が落ちないようにする
verdict=$(jq -Rrn '
  def texts: if type == "string" then . elif type == "array" then map(.text? // "" | strings) | join("\n") else "" end;
  def skill_name: tostring | split(":") | last;
  reduce (inputs | fromjson? | select(type == "object" and (.isSidechain // false) != true)) as $e
    ({simplify: false, dependabot: false, pr_ids: {}};
      ($e.message.content // null) as $c
      | if $e.type == "assistant" and ($c | type) == "array" then
          reduce ($c[] | select(type == "object" and .type == "tool_use")) as $b (.;
            if $b.name == "Skill" then
              ($b.input.skill // "" | skill_name) as $s
              | if $s == "simplify" then .simplify = true
                elif $s == "dependabot-bulk" then .dependabot = true
                else . end
            elif $b.name == "Bash" and (($b.input.command // "") | tostring | test("gh\\s+pr\\s+(create|new)")) then
              .pr_ids[$b.id // ""] = true
            else . end)
        elif $e.type == "user" then
          (if ($c | type) == "string" then $c
           elif ($c | type) == "array" then [$c[] | select(type == "object" and .type == "text") | .text // ""] | join("\n")
           else "" end) as $t
          | (if ($t | test("<command-name>/?([A-Za-z0-9_-]+:)?simplify</command-name>")) then .simplify = true else . end)
          | (if ($t | test("<command-name>/?([A-Za-z0-9_-]+:)?dependabot-bulk</command-name>")) then .dependabot = true else . end)
          | if ($c | type) == "array" then
              reduce ($c[] | select(type == "object" and .type == "tool_result")) as $r (.;
                if .pr_ids[$r.tool_use_id // ""] and ($r.is_error // false) != true
                   and (($r.content // "") | texts | test("github\\.com/[^/[:space:]]+/[^/[:space:]]+/pull/[0-9]+"))
                then .simplify = false | .dependabot = false
                else . end)
            else . end
        else . end)
  | if .simplify then "simplify" elif .dependabot then "dependabot" else "missing" end
' < "$transcript" 2>/dev/null) || exit 0

[[ "$verdict" == "missing" ]] || exit 0

cat >&2 <<'EOF'
[require-simplify-before-pr] このセッションで (前の PR 作成より後に) /simplify が呼ばれていません。
PR ごとに /simplify を実行する決まりです。「変更が小さい」はスキップの理由になりません。
/simplify を実行して指摘を反映 (またはスキップの理由を記録) してから、gh pr create をもう一度実行してください。
Dependabot の統合 PR は dependabot-bulk skill から作れば免除されます。
EOF
exit 2
