#!/usr/bin/env bash
#
# dotfiles の codex/config.toml を ~/.codex/config.toml にマージする。
#
# Codex CLI は ~/.codex/config.toml に対して以下のセクションを動的に書き込む:
#   - [projects.*]      : project の trust 設定
#   - [plugins.*]       : plugin の有効/無効状態
#   - [notice.*]        : 通知履歴 (例: model_migrations)
#   - [tui.*]           : TUI の内部状態 (例: model_availability_nux)
#   - [hooks.state]     : 承認したフックの trusted_hash (再 review を避けるため絶対保護)
#
# これらは「マシン固有」かつ「Codex が運用中に書き込む」ため、dotfiles 側で
# 管理せず、現状を保持したまま base 設定だけを上書きする。
#
# Usage: codex-merge-config.sh <source> <dest>
#

set -euo pipefail

SOURCE="${1:?usage: codex-merge-config.sh <source> <dest>}"
DEST="${2:?usage: codex-merge-config.sh <source> <dest>}"

# dest から保護対象セクションだけを抽出する。
# 保護対象: [projects.*] / [plugins.*] / [notice.*] / [tui.*] / [hooks.state](.* 含む)
# awk の dynamic regex は backslash 解釈が処理系で揺れるため、必ず静的リテラルで書く。
extract_preserved() {
    local file="$1"
    awk '
        BEGIN { keep = 0 }
        /^\[/ {
            if ($0 ~ /^\[(projects|plugins|notice|tui|hooks\.state)([.]|])/) {
                keep = 1
            } else {
                keep = 0
            }
        }
        keep { print }
    ' "$file"
}

preserved=""
if [[ -e "$DEST" ]] && [[ ! -L "$DEST" ]]; then
    preserved=$(extract_preserved "$DEST")
fi

# 既存が symlink (旧 link.sh の挙動) なら削除して新規ファイルに置き換える
if [[ -L "$DEST" ]]; then
    rm "$DEST"
fi

mkdir -p "$(dirname "$DEST")"

# 一時ファイルで構築 → atomic mv で書き込み失敗時に dest が壊れないようにする
tmp=$(mktemp "$DEST.merge.XXXXXX")
trap 'rm -f "$tmp"' EXIT

{
    cat "$SOURCE"
    if [[ -n "$preserved" ]]; then
        # source の末尾が改行で終わっていなければ補う
        if [[ -n "$(tail -c 1 "$SOURCE")" ]]; then
            printf '\n'
        fi
        # base と保護セクションの間に空行を挿入
        printf '\n'
        printf '%s\n' "$preserved"
    fi
} > "$tmp"

mv "$tmp" "$DEST"
trap - EXIT

echo "[codex-merge-config] $DEST (base: $SOURCE, preserved sections kept)"
