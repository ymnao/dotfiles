#!/usr/bin/env bash
#
# PreToolUse hook: 危険な Bash コマンドをブロックする
# exit 0 = 許可, exit 2 = ブロック (stderr がClaude にフィードバックされる)
#

set -euo pipefail

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')

if [[ -z "$command" ]]; then
  exit 0
fi

# --- 破壊的ファイル操作 ---
if echo "$command" | grep -qE '\brm\b.*-[a-zA-Z]*r[a-zA-Z]*f|rm\b.*-[a-zA-Z]*f[a-zA-Z]*r'; then
  # rm -rf のターゲットが危険なパス（/, ~, $HOME, .）かチェック
  if echo "$command" | grep -qE '\brm\b.*\s+(/|~/|\$HOME|\.\./)'; then
    echo "ブロック: rm -rf で危険なパスが指定されています" >&2
    exit 2
  fi
fi

# --- Git 破壊的操作 ---
if echo "$command" | grep -qE 'git\s+push\s+.*(-f|--force|--force-with-lease)'; then
  echo "ブロック: git push --force は禁止されています" >&2
  exit 2
fi

if echo "$command" | grep -qE 'git\s+reset\s+--hard'; then
  echo "ブロック: git reset --hard は禁止されています" >&2
  exit 2
fi

# --- データ流出リスク ---
if echo "$command" | grep -qE '\bcurl\b.*(-d|--data|-X\s*POST|-F|--form|--upload-file)'; then
  echo "ブロック: curl によるデータ送信は確認が必要です" >&2
  exit 2
fi

exit 0
