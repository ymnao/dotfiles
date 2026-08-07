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
#   4. .sandbox.filesystem.denyWrite に ~/.codex/config.toml が含まれる
#      (issue #190: allowWrite の ~/.codex はディレクトリ全体なので、config.toml
#       の notify / mcp_servers / hooks フィールド経由で host 側任意コマンド実行に
#       繋がる。deny-within-allow で config.toml だけ単点 deny する設計)
#   5. .sandbox.filesystem.denyWrite に ~/development/**/.codex/** が含まれる
#      (issue #289: プロジェクト配下の .codex/ を Bash 経路で止める一次防御)
#
# make test の JSON 構文チェック (jq empty) では内容の drift を検出できないため
# 本テストで assert する。issue #184 の failure scenario 参照。
#
# 依存: bash 3.2+ / jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
# INTEGRITY_SETTINGS で検査対象パスを差し替え可能 (selftest 用)。
SETTINGS="${INTEGRITY_SETTINGS:-$REPO_ROOT/claude/settings.json}"

pass=0
fail=0

check_contains() {
  # $1=jq path, $2=期待する要素, $3=説明
  local path="$1"
  local expected="$2"
  local desc="$3"
  # any(.[]?; . == $v) にすることで対象が配列かつ $v が要素として存在する場合のみ true。
  # jq の index() は入力が文字列だと substring 検索して非 null を返し、
  # 誤って allowedDomains が単一文字列に化けた drift を false PASS してしまう
  # (例: "chatgpt.com,auth.openai.com" のカンマ区切り一枚岩) — それを塞ぐ
  if jq -e --arg v "$expected" "$path | any(.[]?; . == \$v)" "$SETTINGS" >/dev/null; then
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
# tilde を quote 内に直書きすると shellcheck SC2088 を踏むので 2 段組みで
# literal を組み立てる。single-quote (`'~/.codex'`) だけでなく double-quote
# (`"~/.codex"`) でも同じ SC2088 が発火するため、素朴な「簡略化」で
# `codex_literal="~/.codex"` にリファクタしないこと。$HOME 展開もさせない —
# JSON 側は "~/.codex" のリテラル文字列で保存されており sandbox runtime が解釈する。
codex_literal='~'
codex_literal="${codex_literal}/.codex"
check_contains '.sandbox.filesystem.allowWrite' "$codex_literal" \
  "claude/settings.json: .sandbox.filesystem.allowWrite に ~/.codex が無い"
# allowWrite が ~/.codex ディレクトリ全体なので、config.toml は denyWrite 側で
# 単点 deny して sandbox escape 経路を塞ぐ (issue #190)。allowWrite を必要
# subpath 列挙に絞る経路は取らない — sqlite の -wal/-shm サイドカーや
# models_cache.json のような「codex 側の実装詳細で増えるパス」に追随できず
# 壊れやすいため、攻撃面が集中している config.toml 1 ファイルを deny する。
check_contains '.sandbox.filesystem.denyWrite' "${codex_literal}/config.toml" \
  "claude/settings.json: .sandbox.filesystem.denyWrite に ~/.codex/config.toml が無い (notify 経由の sandbox escape)"
# プロジェクト配下の .codex/ を sandbox 層で deny する (issue #289)。
#
# この assert が測るのは **エントリが設定に在ること** だけで、
# **実際に書き込みが止まることの証明ではない**。表記を 1 文字変えるだけで
# 静かに無効化されるため (相対表記や `**/` 始まりは警告なしで無視される。
# 2026-08-08 実測)、enforcement の根拠は docs/ai-operations.md §10
# 「denyWrite のパス表記」節の測定記録の側にある。
#
# 前方一致や部分一致ではなく **全文一致** で pin するのはそのため —
# `~/development/**/.codex` のように末尾の `/**` が落ちた形や、
# `**/.codex/**` のように絶対パス始まりでなくなった形は、
# JSON としては妥当で jq の存在検査も通るが sandbox では効かない。
project_codex_glob='~'
project_codex_glob="${project_codex_glob}/development/**/.codex/**"
check_contains '.sandbox.filesystem.denyWrite' "$project_codex_glob" \
  "claude/settings.json: .sandbox.filesystem.denyWrite に ~/development/**/.codex/** が無い (プロジェクト配下の .codex/ が sandbox 層で無防備)"

echo "settings codex domains: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
