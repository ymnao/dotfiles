#!/usr/bin/env bash
#
# PreToolUse hook (Claude Code / Codex CLI 共通): `gh pr|issue` の
# create / edit / comment / review に --body-file / -F で渡す本文へ、textlint の
# AI 文体プリセット (agents/textlint/textlintrc.json) をかける。error があれば
# exit 2 で 1 度だけ止め、指摘を stderr で返して agent に本文を直させる (issue #452)
# 正本: agents/hooks/lint-gh-body.sh
# (claude/hooks/ と codex/hooks/ からは相対 symlink で参照される)
#
# - 1 度止めた本文は 2 回目は通す。同じセッションの同じパス、または同じ内容の
#   どちらかに一致すれば通す (直し続けるループを作らないため)
# - textlint と設定は dotfiles repo から取る。repo はこのスクリプトの置き場所
#   (<repo>/{agents,claude,codex}/hooks/) から導く。他の repo には何も入れない
# - fail-open: jq / textlint が無い、本文ファイルを解決できない (変数展開・stdin・
#   cd 後の相対パス等)、textlint が異常終了した、はいずれも exit 0。文体の検査は
#   防御層ではないので、漏れは欠陥ではない。引数の解析を作り込まないのもそのため
#
# テスト用の上書き: LINT_GH_BODY_TEXTLINT (textlint の実行ファイル)、
# LINT_GH_BODY_STATE_DIR (止めた記録の置き場)

set -uo pipefail

input=$(cat)

case "$input" in
  *gh*--body-file*|*gh*-F*) ;;
  *) exit 0 ;;
esac

command -v jq &>/dev/null || exit 0

command=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[[ -z "$command" ]] && exit 0
payload_cwd=$(printf '%s\n' "$input" | jq -r '.cwd // empty' 2>/dev/null) || payload_cwd=""
session_id=$(printf '%s\n' "$input" | jq -r '.session_id // empty' 2>/dev/null) || session_id=""

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd -P) || exit 0
textlint=${LINT_GH_BODY_TEXTLINT:-$repo_root/node_modules/.bin/textlint}
config="$repo_root/agents/textlint/textlintrc.json"
[[ -x "$textlint" && -f "$config" ]] || exit 0

state_dir=${LINT_GH_BODY_STATE_DIR:-${TMPDIR:-/tmp}/lint-gh-body}

# 値の取り出しは verify-ci-before-pr.sh の extract_flag_value と同じ形
# (double quote → single quote → 裸トークンの順)。共通化しないのは、あちらが
# fail-closed の検査と絡んでいて、文体検査の都合で触らせたくないため
extract_body_file() {
  local segment="$1" v
  v=$(printf '%s\n' "$segment" \
    | sed -nE 's/.*[[:space:]](--body-file|-F)(=|[[:space:]]+)("([^"]*)"|([^[:space:]]+)).*/\4\5/p')
  if [[ -z "$v" || "$v" == \'* ]]; then
    v=$(printf '%s\n' "$segment" \
      | sed -nE "s/.*[[:space:]](--body-file|-F)(=|[[:space:]]+)'([^']*)'.*/\\3/p")
  fi
  printf '%s' "$v"
}

key_of() {
  printf '%s' "$1" | cksum | tr -d ' '
}

segments=$(printf '%s\n' "$command" \
  | grep -oE '(^|[;&|({`[:space:]/\])gh[[:space:]]+(pr|issue)[[:space:]]+(create|new|edit|comment|review)[^;&|]*' \
  || true)
[[ -z "$segments" ]] && exit 0

while IFS= read -r segment; do
  body_file=$(extract_body_file "$segment")
  [[ -z "$body_file" || "$body_file" == "-" || "$body_file" == *'$'* ]] && continue
  if [[ "$body_file" != /* && -n "$payload_cwd" ]]; then
    body_file="$payload_cwd/$body_file"
  fi
  [[ -f "$body_file" && -r "$body_file" ]] || continue

  path_key="path-$(key_of "${session_id}:${body_file}")"
  content_key="content-$(cksum < "$body_file" | tr -d ' ')"
  if [[ -e "$state_dir/$path_key" || -e "$state_dir/$content_key" ]]; then
    continue
  fi

  report=$("$textlint" --config "$config" --format unix --stdin --stdin-filename body.md < "$body_file" 2>/dev/null)
  rc=$?
  # textlint は error があると 1、設定やモジュールの不備は 2 以上で終わる
  [[ $rc -eq 1 ]] || continue

  mkdir -p "$state_dir" 2>/dev/null && : > "$state_dir/$path_key" && : > "$state_dir/$content_key"
  cat >&2 <<EOF
[lint-gh-body] 本文 ($body_file) に AI の文章に多い書き方が見つかりました。
指摘を参考に本文を直してから、同じコマンドを実行し直してください。
直す必要がないと判断した場合は、そのまま実行し直せば今回は通ります (同じ本文で止めるのは 1 度だけ)。

$report
EOF
  exit 2
done <<< "$segments"

exit 0
