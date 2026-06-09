#!/usr/bin/env bash
#
# PreToolUse hook (Codex CLI): 危険な Bash コマンドをブロックする
# exit 0 = 許可, exit 2 = ブロック (stderr が Codex にフィードバックされる)
#

input=$(cat)

case "$input" in
  *rm*|*git*|*codex*|*chmod*|*sudo*) ;;
  *) exit 0 ;;
esac

if ! command -v jq &>/dev/null; then
  exit 0
fi

command=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty')

if [[ -z "$command" ]]; then
  exit 0
fi

# --- 破壊的ファイル操作 ---
rm_rf_pattern='(^|[;&|({`[:space:]])rm[[:space:]]+('
rm_rf_pattern+='([^;&|]*[[:space:]])?-[a-zA-Z]*[rR][a-zA-Z]*f[a-zA-Z]*'
rm_rf_pattern+='|([^;&|]*[[:space:]])?-[a-zA-Z]*f[a-zA-Z]*[rR][a-zA-Z]*'
rm_rf_pattern+='|([^;&|]*[[:space:]])?(--recursive|-[a-zA-Z]*[rR][a-zA-Z]*)[^;&|]*(--force|[[:space:]]-[a-zA-Z]*f[a-zA-Z]*)'
rm_rf_pattern+='|([^;&|]*[[:space:]])?(--force|-[a-zA-Z]*f[a-zA-Z]*)[^;&|]*(--recursive|[[:space:]]-[a-zA-Z]*[rR][a-zA-Z]*)'
rm_rf_pattern+=')'
if printf '%s\n' "$command" | grep -qE "$rm_rf_pattern"; then
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

# --- .codex ディレクトリへの参照を全面ブロック ---
# 書き込みコマンドの列挙ではすべてのリダイレクト/エイリアスを網羅できないため、
# コマンド全体に対して .codex を独立トークンとして検出する。
# 例: `> .codex/config.toml`, `install -d .codex`, `printf x > .codex/config.toml` 等
if printf '%s\n' "$command" | grep -qE '(^|[[:space:]/"`(>]|\\)\.codex([/[:space:]"`)]|\\|$)'; then
  echo "ブロック: プロジェクト内の .codex/ ディレクトリへの参照は禁止されています（Cymulate notify エスケープ対策）" >&2
  exit 2
fi

# --- chmod 777 ---
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])chmod[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*777([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: chmod 777 は禁止されています" >&2
  exit 2
fi

# --- sudo ---
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])sudo[[:space:]]'; then
  echo "ブロック: sudo は禁止されています" >&2
  exit 2
fi

exit 0
