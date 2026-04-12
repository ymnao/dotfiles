#!/usr/bin/env bash
#
# PreToolUse hook: 危険な Bash コマンドをブロックする
# exit 0 = 許可, exit 2 = ブロック (stderr がClaude にフィードバックされる)
#

input=$(cat)

# jq が未インストールの場合は fail-open（ブロックせず通す）
if ! command -v jq &>/dev/null; then
  exit 0
fi

command=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty')

if [[ -z "$command" ]]; then
  exit 0
fi

# --- 破壊的ファイル操作 ---
# rm に再帰(-r/-R/--recursive)と強制(-f/--force)の両方が同一コマンド内に含まれるかチェック
# [^;&|]* で区切り文字(; && || |)を超えないことを保証し、別コマンドとの誤検知を防止
rm_rf_pattern='(^|[;&|({`[:space:]])rm[[:space:]]+('
rm_rf_pattern+='([^;&|]*[[:space:]])?-[a-zA-Z]*[rR][a-zA-Z]*f[a-zA-Z]*'
rm_rf_pattern+='|([^;&|]*[[:space:]])?-[a-zA-Z]*f[a-zA-Z]*[rR][a-zA-Z]*'
rm_rf_pattern+='|([^;&|]*[[:space:]])?(--recursive|-[a-zA-Z]*[rR][a-zA-Z]*)[^;&|]*(--force|[[:space:]]-[a-zA-Z]*f[a-zA-Z]*)'
rm_rf_pattern+='|([^;&|]*[[:space:]])?(--force|-[a-zA-Z]*f[a-zA-Z]*)[^;&|]*(--recursive|[[:space:]]-[a-zA-Z]*[rR][a-zA-Z]*)'
rm_rf_pattern+=')'
if printf '%s\n' "$command" | grep -qE "$rm_rf_pattern"; then
  # rm -rf のターゲットが危険なパス（/, ~, $HOME, .., .）かチェック
  if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])rm[[:space:]].*[[:space:]]+(/|~/|\$HOME|\.\.(/|[[:space:]]|[;&|)}`]|$)|\./?([[:space:]]|[;&|)}`]|$))'; then
    echo "ブロック: rm -rf で危険なパスが指定されています" >&2
    exit 2
  fi
fi

# --- Git 破壊的操作 ---
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])git[[:space:]]+push[[:space:]]+([^;&|]*[[:space:]])?(--force|--force-with-lease(=[^[:space:]]*)?|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: git push --force は禁止されています" >&2
  exit 2
fi

if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])git[[:space:]]+reset[[:space:]]+--hard([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: git reset --hard は禁止されています" >&2
  exit 2
fi

exit 0
