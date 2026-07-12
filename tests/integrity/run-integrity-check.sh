#!/usr/bin/env bash
set -uo pipefail

# エージェント設定の改ざん検知 (integrity check)。
#
# 背景: エージェント設定ファイル自体が攻撃対象になる実例が確認されている
# (2026-05 Mitiga: 悪性 npm の postinstall が ~/.claude.json を書き換えて
# MCP 通信を攻撃者プロキシへ誘導しトークンを窃取)。このリポジトリの設定は
# ほぼすべて dotfiles からの symlink なので、「symlink のまま正しい実体を
# 指しているか」の検査で安価に改ざん・すり替えを検出できる。
#
# 検査:
#   1. ~/.claude 配下の管理対象が期待どおりの symlink か
#   2. ~/.codex 配下も同様。config.toml はマージ方式なので
#      「先頭が dotfiles の base と一致する実体ファイル」であること
#   3. ~/.claude.json の MCP 定義 (グローバル + プロジェクト単位) が
#      許可リスト (allowed-mcp.txt) に収まっているか
#
# 検知時: exit 1 で失敗し、期待と実際を列挙する。自動修復はしない
# (改ざんかもしれないものを黙って直すのは危険。make link の再実行は人間が判断)。
#
# 環境変数 (テスト用):
#   INTEGRITY_HOME     — $HOME の代わりに検査するルート
#   INTEGRITY_DOTFILES — dotfiles リポジトリルートの上書き
#
# ~/.claude が無い環境 (CI・未セットアップ機) では skip (fail-open)。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
DOTFILES="${INTEGRITY_DOTFILES:-$REPO_ROOT}"
H="${INTEGRITY_HOME:-$HOME}"

if [ ! -d "$H/.claude" ]; then
  echo "integrity: SKIP ($H/.claude が無い未セットアップ環境)"
  exit 0
fi

fail=0

expect_link() {
  # $1=symlink パス, $2=期待する実体
  if [ ! -e "$1" ] && [ ! -L "$1" ]; then
    echo "NG: $1 が存在しない (make link 未実行?)"
    fail=1
    return
  fi
  if [ ! -L "$1" ]; then
    echo "NG: $1 が symlink でなく実体ファイル (上書き・改ざんの可能性)"
    fail=1
    return
  fi
  local t
  t=$(readlink "$1")
  if [ "$t" != "$2" ]; then
    echo "NG: $1 -> $t (期待: $2)"
    fail=1
  fi
}

# 1. ~/.claude 配下
expect_link "$H/.claude/CLAUDE.md"     "$DOTFILES/agents/AGENTS.md"
expect_link "$H/.claude/settings.json" "$DOTFILES/claude/settings.json"
expect_link "$H/.claude/skills"        "$DOTFILES/claude/skills"
expect_link "$H/.claude/hooks"         "$DOTFILES/claude/hooks"
expect_link "$H/.claude/agents"        "$DOTFILES/claude/agents"
expect_link "$H/.claude/rules"         "$DOTFILES/claude/rules"
expect_link "$H/.claude/statusline.sh" "$DOTFILES/claude/statusline.sh"

# 2. ~/.codex 配下 (codex 未セットアップ機ではスキップ)
if [ -d "$H/.codex" ]; then
  expect_link "$H/.codex/AGENTS.md"  "$DOTFILES/codex/AGENTS.md"
  expect_link "$H/.codex/hooks.json" "$DOTFILES/codex/hooks.json"
  expect_link "$H/.codex/hooks"      "$DOTFILES/codex/hooks"
  for d in "$DOTFILES/codex/skills"/*/; do
    [ -d "$d" ] || continue
    expect_link "$H/.codex/skills/$(basename "$d")" "${d%/}"
  done

  cfg="$H/.codex/config.toml"
  base="$DOTFILES/codex/config.toml"
  if [ -L "$cfg" ]; then
    echo "NG: $cfg が symlink (マージ方式の実体ファイルのはず)"
    fail=1
  elif [ -f "$cfg" ] && [ -f "$base" ]; then
    base_size=$(wc -c <"$base" | tr -d ' ')
    if ! head -c "$base_size" "$cfg" | cmp -s - "$base"; then
      echo "NG: $cfg の base 部分が dotfiles の codex/config.toml と一致しない"
      fail=1
    fi
  fi
fi

# 3. ~/.claude.json の MCP 定義
cj="$H/.claude.json"
allowlist="$SCRIPT_DIR/allowed-mcp.txt"
if [ -f "$cj" ] && command -v jq >/dev/null 2>&1; then
  found=$(jq -r '
    [((.mcpServers // {}) | keys[]),
     ((.projects // {}) | to_entries[] | (.value.mcpServers // {}) | keys[])]
    | .[]' "$cj" 2>/dev/null | sort -u)
  if [ -n "$found" ]; then
    allowed=$(grep -vE '^[[:space:]]*(#|$)' "$allowlist" 2>/dev/null || true)
    unknown=""
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      if ! printf '%s\n' "$allowed" | grep -qxF "$name"; then
        unknown="$unknown $name"
      fi
    done <<EOF
$found
EOF
    if [ -n "$unknown" ]; then
      echo "NG: ~/.claude.json に許可リスト外の MCP 定義:$unknown"
      echo "    正当な追加なら審査 (docs/ai-operations.md §5) のうえ tests/integrity/allowed-mcp.txt に追記する"
      fail=1
    fi
  fi
fi

if [ "$fail" = 0 ]; then
  echo "integrity: OK"
  exit 0
fi
echo "integrity: FAILED (改ざん・すり替えの可能性を確認すること。設定を作り直す場合は make link)"
exit 1
