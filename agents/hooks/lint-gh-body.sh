#!/usr/bin/env bash
#
# PreToolUse hook (Claude Code / Codex CLI 共通): `gh pr|issue` の
# create / edit / comment / review に --body-file / -F で渡す本文へ、textlint の
# AI 文体プリセット (agents/textlint/textlintrc.json) をかける。error があれば
# exit 2 で 1 度だけ止め、指摘を stderr で返して agent に本文を直させる (issue #452)
# 正本: agents/hooks/lint-gh-body.sh
# (claude/hooks/ と codex/hooks/ からは相対 symlink で参照される)
#
# 同じセッションの同じパス、または同じ内容の本文は 2 回目は通す (直し続けるループを
# 作らないため)。解決できない形 (変数展開・stdin・cd 後の相対パス等) や textlint の
# 不在・異常終了はすべて通す。文体の検査は防御層ではなく、漏れは欠陥ではないので、
# 引数の解析も作り込まない
#
# テスト用の上書き: LINT_GH_BODY_TEXTLINT (textlint の実行ファイル)、
# LINT_GH_BODY_STATE_DIR (止めた記録の置き場)

set -uo pipefail

input=$(cat)

case "$input" in
  *gh*pr*|*gh*issue*) ;;
  *) exit 0 ;;
esac
case "$input" in
  *--body-file*|*-F*) ;;
  *) exit 0 ;;
esac

command -v jq &>/dev/null || exit 0

command=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[[ -z "$command" ]] && exit 0

segments=$(printf '%s\n' "$command" \
  | grep -oE '(^|[;&|({`[:space:]/\])gh[[:space:]]+(pr|issue)[[:space:]]+(create|new|edit|comment|review)[^;&|]*' \
  || true)
[[ -z "$segments" ]] && exit 0

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd -P) || exit 0
textlint=${LINT_GH_BODY_TEXTLINT:-$repo_root/node_modules/.bin/textlint}
config="$repo_root/agents/textlint/textlintrc.json"
[[ -x "$textlint" && -f "$config" ]] || exit 0

payload_cwd=$(printf '%s\n' "$input" | jq -r '.cwd // empty' 2>/dev/null) || payload_cwd=""
session_id=$(printf '%s\n' "$input" | jq -r '.session_id // empty' 2>/dev/null) || session_id=""
state_dir=${LINT_GH_BODY_STATE_DIR:-${TMPDIR:-/tmp}/lint-gh-body}

# verify-ci-before-pr.sh の extract_flag_value と同じ抽出だが共通化しない。
# あちらは fail-closed の検査と絡んでおり、文体検査の都合で触らせたくない
extract_body_file() {
  printf '%s\n' "$1" \
    | sed -nE "s/.*[[:space:]](--body-file|-F)(=|[[:space:]]+)(\"([^\"]*)\"|'([^']*)'|([^[:space:]]+)).*/\\4\\5\\6/p"
}

checksum() {
  cksum | tr -d ' '
}

while IFS= read -r segment; do
  body_file=$(extract_body_file "$segment")
  [[ -z "$body_file" || "$body_file" == "-" || "$body_file" == *'$'* ]] && continue
  if [[ "$body_file" != /* && -n "$payload_cwd" ]]; then
    body_file="$payload_cwd/$body_file"
  fi
  [[ -f "$body_file" && -r "$body_file" ]] || continue

  path_key="path-$(printf '%s' "${session_id}:${body_file}" | checksum)"
  [[ -e "$state_dir/$path_key" ]] && continue
  content_key="content-$(checksum < "$body_file")"
  [[ -e "$state_dir/$content_key" ]] && continue

  report=$("$textlint" --config "$config" --format unix --stdin --stdin-filename body.md < "$body_file" 2>/dev/null)
  # 2 以上は設定やモジュールの不備なので通す
  [[ $? -eq 1 ]] || continue

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
