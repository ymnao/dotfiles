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
# コマンドを区切り文字(; && || |)で分割し、同一セグメント内でrm -rfをチェック
while IFS= read -r segment; do
  [[ "$segment" =~ ^[[:space:]]*$ ]] && continue
  # rm に再帰(-r/-R/--recursive)と強制(-f/--force)の両方が含まれるかチェック
  if printf '%s\n' "$segment" | grep -qE '(^|[[:space:]])rm[[:space:]]+(.*[[:space:]])?(--recursive|-[a-zA-Z]*[rR][a-zA-Z]*)([[:space:]]|$)' \
    && printf '%s\n' "$segment" | grep -qE '(^|[[:space:]])rm[[:space:]]+(.*[[:space:]])?(--force|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|$)'; then
    # rm -rf のターゲットが危険なパス（/, ~, $HOME, .., .）かチェック
    if printf '%s\n' "$segment" | grep -qE '(^|[[:space:]])rm[[:space:]].*[[:space:]]+(/|~/|\$HOME|\.\.(/|[[:space:]]|$)|\./?([[:space:]]|$))'; then
      echo "ブロック: rm -rf で危険なパスが指定されています" >&2
      exit 2
    fi
  fi
done < <(printf '%s\n' "$command" | awk '{gsub(/\|\||&&|[;|]/, "\n"); print}')

# --- Git 破壊的操作 ---
if printf '%s\n' "$command" | grep -qE 'git[[:space:]]+push[[:space:]]+(.*[[:space:]])?(--force|--force-with-lease(=[^[:space:]]*)?|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|$)'; then
  echo "ブロック: git push --force は禁止されています" >&2
  exit 2
fi

if printf '%s\n' "$command" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+reset[[:space:]]+--hard([[:space:]]|$)'; then
  echo "ブロック: git reset --hard は禁止されています" >&2
  exit 2
fi

exit 0
