#!/usr/bin/env bash
#
# PostToolUse hook (Codex CLI): ツール出力にシークレットが含まれていないか検査する
#
# 固定プレフィックスマッチでシークレットパターンを検出。
# 検出した場合は exit 2 でブロックし、出力がモデルに渡されるのを防ぐ。
#
# exit 0 = 許可, exit 2 = ブロック
#

input=$(cat)

if ! command -v jq &>/dev/null; then
  exit 0
fi

# ツール出力を取得（Codex CLI の PostToolUse フィールド名は tool_response）
output=$(printf '%s\n' "$input" | jq -r '(.tool_response // "") | if type == "string" then . else tostring end')

if [[ -z "$output" ]]; then
  exit 0
fi

# シークレットパターン（固定プレフィックスマッチ）
patterns=(
  # AWS
  'AKIA[0-9A-Z]{16}'
  'aws_secret_access_key'
  'AWS_SECRET_ACCESS_KEY'
  # GitHub
  'ghp_[a-zA-Z0-9]{36}'
  'gho_[a-zA-Z0-9]{36}'
  'ghs_[a-zA-Z0-9]{36}'
  'ghr_[a-zA-Z0-9]{36}'
  'github_pat_[a-zA-Z0-9_]{22,}'
  # Slack
  'xoxb-[0-9]'
  'xoxp-[0-9]'
  'xoxa-[0-9]'
  'xoxo-[0-9]'
  # Stripe
  'sk_live_[a-zA-Z0-9]'
  'rk_live_[a-zA-Z0-9]'
  # Private keys
  '-----BEGIN[[:space:]]+(RSA|DSA|EC|OPENSSH|PGP)[[:space:]]+PRIVATE[[:space:]]+KEY-----'
  # Generic API key patterns
  'ANTHROPIC_API_KEY'
  'OPENAI_API_KEY'
  'sk-ant-[a-zA-Z0-9]'
  'sk-[a-zA-Z0-9]{20,}'
)

IFS='|'
combined_pattern="${patterns[*]}"
unset IFS

matched=$(printf '%s\n' "$output" | grep -oE "$combined_pattern" | head -3)

if [[ -n "$matched" ]]; then
  echo "ブロック: ツール出力にシークレットが検出されました。出力をモデルに渡しません。" >&2
  echo "検出パターン:" >&2
  while IFS= read -r line; do
    echo "  ${line:0:8}********" >&2
  done <<<"$matched"
  exit 2
fi

exit 0
