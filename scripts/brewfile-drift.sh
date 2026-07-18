#!/bin/bash
# Brewfile 未追跡のインストール済みパッケージ (formula leaves + cask) を検出する。
#
# `make update` が既に Brewfile → installed 方向 (brew bundle check) を担当するので、
# ここは installed → Brewfile 方向 (未追跡 drift) 専用。
# `brew bundle dump` は Brewfile 手動編集の構造 (セクション・コメント・trusted:) を
# 破壊するため使わない (CLAUDE.md 参照)。
#
# tap 付き記述 (例: "supabase/tap/supabase") は最終 / 以降で正規化して突き合わせる。

set -euo pipefail

cd "$(dirname "$0")/.."

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/brewfile-drift.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

# kind: brew-cli 側の listing コマンド, Brewfile 側の prefix
list_formulae() { brew leaves 2>/dev/null; }
list_casks() { brew list --cask 2>/dev/null; }

normalize() { awk -F/ '{print $NF}' | sort; }

extract_brewfile() {
    # $1: "brew" or "cask"
    grep -E "^$1 \"" Brewfile | sed "s/^$1 \"\([^\"]*\)\".*/\1/"
}

rc=0
for kind in formula cask; do
    case "$kind" in
        formula) list_formulae ;;
        cask)    list_casks ;;
    esac | normalize > "$tmpdir/installed-$kind"

    brewfile_prefix=brew
    [ "$kind" = cask ] && brewfile_prefix=cask
    extract_brewfile "$brewfile_prefix" | normalize > "$tmpdir/brewfile-$kind"

    drift=$(comm -23 "$tmpdir/installed-$kind" "$tmpdir/brewfile-$kind")
    if [ -n "$drift" ]; then
        echo "==> ${kind}: installed but not in Brewfile"
        echo "$drift" | sed 's/^/  /'
        rc=1
    fi
done

if [ "$rc" -eq 0 ]; then
    echo "OK: no drift (installed leaves/casks all tracked in Brewfile)"
else
    echo ""
    echo "HINT: Brewfile に追記するか、brew uninstall で削除する (make brewfile は使わない)"
fi

exit "$rc"
