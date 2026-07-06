#!/usr/bin/env bash
#
# PostToolUse hook (Claude Code): Edit/Write 後の自動フォーマット
# 正本: agents/hooks/post-format.sh
# (PR6 適用後は claude/hooks/ から相対 symlink。PR6 未適用なら claude/hooks/ に直接配置)
#
# 方針:
#   - リポジトリに formatter の設定がある場合のみ実行する (設定 = リポジトリの意思表示。
#     方針のないリポジトリを勝手に整形しない)
#   - formatter はリポジトリローカルのもののみ使う (node_modules/.bin, .venv/bin)。
#     グローバルツールに依存しない
#   - 常に exit 0。フォーマットは装飾であり、失敗でターンを止めない
#
# 対応マッピング:
#   js/ts/json/css/md/yaml 等 → prettier (設定ファイル or package.json "prettier" キー必須)
#   py                        → ruff format (pyproject.toml に [tool.ruff] 必須)
#   shell は v1 では対象外 (shfmt はリポジトリローカル運用が一般的でないため)
#
# 依存: jq / git (無ければ何もしない)

set -uo pipefail

input=$(cat)

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty')
case "$tool_name" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0

dir=$(dirname "$file")
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0

ext="${file##*.}"
ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')

has_prettier_config() {
  local f
  for f in .prettierrc .prettierrc.json .prettierrc.yml .prettierrc.yaml \
           .prettierrc.json5 .prettierrc.js .prettierrc.cjs .prettierrc.mjs \
           .prettierrc.toml prettier.config.js prettier.config.cjs prettier.config.mjs; do
    [ -f "$root/$f" ] && return 0
  done
  if [ -f "$root/package.json" ] && jq -e '.prettier' "$root/package.json" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

case "$ext" in
  js|jsx|ts|tsx|mjs|cjs|json|css|scss|less|md|yml|yaml|html|vue)
    prettier_bin="$root/node_modules/.bin/prettier"
    [ -x "$prettier_bin" ] || exit 0
    has_prettier_config || exit 0
    "$prettier_bin" --write "$file" >/dev/null 2>&1 || true
    ;;
  py)
    ruff_bin="$root/.venv/bin/ruff"
    [ -x "$ruff_bin" ] || exit 0
    { [ -f "$root/pyproject.toml" ] && grep -q '^\[tool\.ruff' "$root/pyproject.toml"; } || exit 0
    "$ruff_bin" format "$file" >/dev/null 2>&1 || true
    ;;
esac

exit 0
