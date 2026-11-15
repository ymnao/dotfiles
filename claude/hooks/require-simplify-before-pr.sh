#!/usr/bin/env bash
#
# PreToolUse hook (Claude Code 専用): `gh pr create` (alias `gh pr new` 含む) の前に、
# このセッションで /simplify が呼ばれているかを transcript から判定し、無ければ止める (#508)
#
# - 対象: 入力の cwd の repo ルートに .claude/simplify-gate.conf がある repo だけ (opt-in)
# - 数える範囲: 直前に作成した `gh pr create` より後 (PR 単位)。compaction ではリセットしない
#   (/simplify の効果は適用済みの修正としてコードに残るため、やり直させても得るものが無い)
# - 呼び出しの形: Skill tool の tool_use (agent が呼んだ) と <command-name> タグ (user が打った)
# - 免除: 同じ範囲で dependabot-bulk skill が呼ばれている (Dependabot 由来の統合 PR)
# - --draft は免除しない (CI 待ちの bypass とは目的が違い、draft も後で ready になる)
# - transcript が無い・読めない・cwd が repo でない・jq / git が無いときは判定できないので通す
# - exit 0 = 許可, exit 2 = block (stderr が Claude にフィードバックされる)

# Why not -e: jq の失敗を fail-open の分岐で自分で扱う
set -uo pipefail

input=$(cat)

case "$input" in
  *gh*pr*create*|*gh*pr*new*) ;;
  *) exit 0 ;;
esac

command -v jq &>/dev/null || exit 0
command -v git &>/dev/null || exit 0

# command 位置の `gh pr create|new`。verify-ci-before-pr.sh の grep -E の式と同じ集合を受理する
# Why not 文字クラスの `\` を 1 個: Oniguruma では `\]` がクラスを閉じない (ERE とは逆)
PR_RE='(^|[;&|({`[:space:]/\\])([A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*[[:space:]]+)*gh[[:space:]]+pr[[:space:]]+(create|new)'

# Why not grep -q へ pipe: pipefail 下で grep が先に終わると printf の SIGPIPE が不一致扱いになる
vals=$(printf '%s' "$input" | jq -r --arg re "$PR_RE" \
  'select((.tool_input.command // "" | tostring | test($re))) | (.cwd // ""), (.transcript_path // "")' 2>/dev/null) || exit 0
[[ -n "$vals" ]] || exit 0
{
  IFS= read -r cwd
  IFS= read -r transcript
} <<EOF
$vals
EOF

# opt-in: repo ルートに .claude/simplify-gate.conf がある repo だけで止める (stop-gate.conf と同じ方式)。
# repo は入力の cwd で決める (hook プロセスの cwd は worktree でも元のチェックアウトになりうる。#471)
[[ -n "$cwd" && -d "$cwd" ]] || exit 0
repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
[[ -f "$repo_root/.claude/simplify-gate.conf" ]] || exit 0

[[ -n "$transcript" && -f "$transcript" && -r "$transcript" ]] || exit 0

# 前の PR 作成は「tool_result が error でなく、本文に PR の URL がある」で作成済みとみなす
# (is_error だけだと PR を作らずに成功した --web 等も数える)。run_in_background の結果は
# 起動の通知だけで URL を含まないので、error でなければ作成済みに倒す (background の中で
# 後から失敗しても作成済みとして扱う。/simplify のやり直しを求める側に倒れる)
# Why not `fromjson?` を外す: 書き込み途中の末尾行や壊れた行で全体が落ちないようにする
# Why not タグを本文のどこでも数える: subagent の報告や要約の引用で gate が満たされる
ok=$(jq -Rrn --arg re "$PR_RE" '
  def texts: if type == "string" then . elif type == "array" then map(.text? | strings) | join("\n") else "" end;
  def gated: "(simplify|dependabot-bulk)";
  def events:
    .message.content as $c
    | if .type == "assistant" then
        $c | arrays[] | select(.type? == "tool_use")
        | if .name == "Skill" and (.input.skill // "" | tostring | test("^([^:]*:)?" + gated + "$")) then {ok: true}
          elif .name == "Bash" and (.input.command // "" | tostring | test($re)) then {pr: (.id // ""), bg: (.input.run_in_background == true)}
          else empty end
      elif .type == "user" then
        (select($c | texts | test("^(<command-message>[^<]*</command-message>\\s*)?<command-name>/?([A-Za-z0-9_-]+:)?" + gated + "</command-name>")) | {ok: true}),
        ($c | arrays[] | select(.type? == "tool_result" and .is_error != true)
          | {done: (.tool_use_id // ""), url: (.content | texts | test("github\\.com/[^/[:space:]]+/[^/[:space:]]+/pull/[0-9]+"))})
      else empty end;
  reduce (inputs | fromjson? | objects | select(.isSidechain != true) | events) as $v
    ({ok: false, prs: {}};
      if $v.ok then .ok = true
      elif $v.pr then .prs[$v.pr] = {bg: $v.bg}
      elif .prs[$v.done] and ($v.url or .prs[$v.done].bg) then .ok = false
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
