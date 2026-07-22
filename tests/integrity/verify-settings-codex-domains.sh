#!/usr/bin/env bash
#
# claude/settings.json の codex-review 必須設定が欠けていないことを検証する。
#
# 検証項目:
#   1. .sandbox.network.allowedDomains に chatgpt.com が含まれる
#      (codex CLI の実 API call が chatgpt.com/backend-api/ を叩く)
#   2. .sandbox.network.allowedDomains に auth.openai.com が含まれる
#      (token refresh の OAuth endpoint。chatgpt.com だけでは refresh 失敗)
#   3. .sandbox.filesystem.allowWrite に ~/.codex が含まれる
#      (codex CLI が sessions/history/auth.json 等を書き込む)
#
# make test の JSON 構文チェック (jq empty) では内容の drift を検出できないため
# 本テストで assert する。issue #184 の failure scenario 参照。
#
# 依存: bash 3.2+ / jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
SETTINGS="$REPO_ROOT/claude/settings.json"

pass=0
fail=0

check_contains() {
  # $1=jq path, $2=期待する要素, $3=説明
  local path="$1"
  local expected="$2"
  local desc="$3"
  if jq -e --arg v "$expected" "$path | index(\$v)" "$SETTINGS" >/dev/null; then
    pass=$((pass + 1))
  else
    echo "FAIL: $desc"
    fail=$((fail + 1))
  fi
}

check_contains '.sandbox.network.allowedDomains' 'chatgpt.com' \
  "claude/settings.json: .sandbox.network.allowedDomains に chatgpt.com が無い"
check_contains '.sandbox.network.allowedDomains' 'auth.openai.com' \
  "claude/settings.json: .sandbox.network.allowedDomains に auth.openai.com が無い (token refresh で 401)"
# tilde を quote 内に直書きすると shellcheck SC2088 (tilde 非展開) を踏むので
# 2 段組みで literal を組み立てる ($HOME 展開はさせない — JSON 側は "~/.codex"
# のリテラル文字列で保存されており sandbox runtime が解釈する)
codex_literal='~'
codex_literal="${codex_literal}/.codex"
check_contains '.sandbox.filesystem.allowWrite' "$codex_literal" \
  "claude/settings.json: .sandbox.filesystem.allowWrite に ~/.codex が無い"

echo "settings codex domains: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
