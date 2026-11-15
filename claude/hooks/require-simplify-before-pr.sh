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

# command 位置の判定は verify-ci-before-pr.sh と同じ式に揃える (下の jq の PR_RE も同じ)
if ! printf '%s\n' "$command" \
  | grep -qE '(^|[;&|({`[:space:]/\])([A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*[[:space:]]+)*gh[[:space:]]+pr[[:space:]]+(create|new)'; then
  exit 0
fi

transcript=$(printf '%s\n' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
[[ -n "$transcript" && -f "$transcript" && -r "$transcript" ]] || exit 0

# 前の PR 作成の成否は tool_result の本文に PR の URL があるかで見る。is_error だけだと
# PR を作らずに成功したコマンドもリセットに数えてしまう
# Why not `fromjson?` を外す: 書き込み途中の末尾行や壊れた行で全体が落ちないようにする
# Why not 文字クラスの `\` を 1 個: Oniguruma では `\]` がクラスを閉じない (ERE とは逆)
ok=$(jq -Rrn '
  def texts: if type == "string" then . elif type == "array" then map(.text? | strings) | join("\n") else "" end;
  def gated: "(simplify|dependabot-bulk)";
  def PR_RE: "(^|[;&|({`[:space:]/\\\\])([A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*[[:space:]]+)*gh[[:space:]]+pr[[:space:]]+(create|new)";
  def events:
    .message.content as $c
    | if .type == "assistant" then
        $c | arrays[] | select(.type? == "tool_use")
        | if .name == "Skill" and (.input.skill // "" | tostring | test("^([^:]*:)?" + gated + "$")) then {ok: true}
          elif .name == "Bash" and (.input.command // "" | tostring | test(PR_RE)) then {pr: (.id // "")}
          else empty end
      elif .type == "user" then
        (select($c | texts | test("<command-name>/?([A-Za-z0-9_-]+:)?" + gated + "</command-name>")) | {ok: true}),
        ($c | arrays[] | select(.type? == "tool_result" and .is_error != true
            and (.content | texts | test("github\\.com/[^/[:space:]]+/[^/[:space:]]+/pull/[0-9]+")))
          | {done: (.tool_use_id // "")})
      else empty end;
  reduce (inputs | fromjson? | objects | select(.isSidechain != true) | events) as $v
    ({ok: false, prs: {}};
      if $v.ok then .ok = true
      elif $v.pr then .prs[$v.pr] = true
      elif .prs[$v.done] then .ok = false
      else . end)
  | .ok
' < "$transcript" 2>/dev/null) || exit 0

[[ "$ok" == "false" ]] || exit 0

cat >&2 <<'EOF'
[require-simplify-before-pr] このセッションで (前の PR 作成より後に) /simplify が呼ばれていません。
PR ごとに /simplify を実行する決まりです。「変更が小さい」はスキップの理由になりません。
/simplify を実行して指摘を反映 (またはスキップの理由を記録) してから、gh pr create をもう一度実行してください。
Dependabot の統合 PR は dependabot-bulk skill から作れば免除されます。
EOF
exit 2
