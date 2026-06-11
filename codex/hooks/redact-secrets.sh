#!/usr/bin/env bash
#
# PostToolUse hook (Codex CLI): ツール出力にシークレットが含まれていないか検査する
#
# 値形式が判別可能なトークンは prefix マッチ、AWS secret 等の不定形値は
# 「変数名+代入+値」の形式で検出する。変数名の単純な言及はブロックしない。
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

# シークレットパターン
patterns=(
  # AWS
  'AKIA[0-9A-Z]{16}'
  # 機密環境変数への値付き代入（NAME=value / NAME: value / "NAME": "value"）
  # 名前の言及だけではブロックしない（README / CI 設定の読み取りを妨げないため）
  "(AWS_SECRET_ACCESS_KEY|aws_secret_access_key|ANTHROPIC_API_KEY|OPENAI_API_KEY)['\"]?[[:space:]]*[=:][[:space:]]*['\"]?[A-Za-z0-9/+_-]{16,}"
  # GitHub
  'ghp_[a-zA-Z0-9]{36}'
  'gho_[a-zA-Z0-9]{36}'
  'ghs_[a-zA-Z0-9]{36}'
  'ghr_[a-zA-Z0-9]{36}'
  'ghu_[a-zA-Z0-9]{36}'
  'github_pat_[a-zA-Z0-9_]{22,}'
  # Slack (bot / user / app-config / session / app-level / refresh)
  'xox[bpas]-[0-9]'
  'xapp-[0-9]'
  'xoxe[.-][a-zA-Z0-9]'
  # Stripe
  'sk_live_[a-zA-Z0-9]'
  'rk_live_[a-zA-Z0-9]'
  # npm / GitLab / Google
  'npm_[a-zA-Z0-9]{36}'
  'glpat-[a-zA-Z0-9_-]{20}'
  'AIza[0-9A-Za-z_-]{35}'
  # JWT（header.payload — JSON の {" は base64url で eyJ になるため両セグメントの先頭を判定）
  'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+'
  # Private keys（PKCS#8 の型語なし / ENCRYPTED / PGP の KEY BLOCK 終端も検出）
  '-----BEGIN([[:space:]]+[A-Z0-9]+)*[[:space:]]+PRIVATE[[:space:]]+KEY([[:space:]]+BLOCK)?-----'
  # OpenAI / Anthropic
  'sk-ant-[a-zA-Z0-9_-]'
  'sk-proj-[a-zA-Z0-9_-]{20,}'
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
