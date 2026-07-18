#!/usr/bin/env bash
#
# Brewfile 未追跡のインストール済みパッケージ (formula leaves + cask) を検出する。
#
# `make update` が既に Brewfile → installed 方向 (brew bundle check) を担当するので、
# ここは installed → Brewfile 方向 (未追跡 drift) 専用。
# `brew bundle dump` は Brewfile 手動編集の構造 (セクション・コメント・trusted:) を
# 破壊するため使わない (CLAUDE.md 参照)。
#
# tap 付き記述 (例: "supabase/tap/supabase") は最終 / 以降で正規化して突き合わせる。

# rc 変数で drift 有無を管理し末尾でまとめて exit するため、set -e は付けない
# (claude/rules/shell.md)。grep の no-match (exit 1) で無診断終了することを避ける。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh" || { echo "brewfile-drift: lib/log.sh not found" >&2; exit 1; }

cd "$SCRIPT_DIR/.." || error "cd to repo root failed"

command -v brew >/dev/null || error "brew not installed"

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/brewfile-drift.XXXXXX") || error "mktemp failed"
trap 'rm -rf "$tmpdir"' EXIT

normalize() { awk -F/ '{print $NF}' | sort; }

# $1: kind label (formula|cask)
# $2: Brewfile 側の prefix (brew|cask)
# $3..: brew CLI 側の listing コマンド
#
# 各 pipeline を一時ファイルに書き出して個別に exit code を検査する。
# process substitution は生成 pipeline の失敗を comm に伝播できず、
# 途中クラッシュで false-negative (drift なし表示) を起こす。
check_drift() {
    local kind=$1 prefix=$2
    shift 2
    # stderr は一旦捕捉し、pipeline 失敗時のみ表示する。brew の tap 側 deprecation
    # 警告等を drift レポートに混ぜず、かつ本当の失敗は診断可能にする。
    "$@" 2> "$tmpdir/list-$kind.err" | normalize > "$tmpdir/installed-$kind"
    # shellcheck disable=SC2181  # pipefail 下で $? はパイプ全体の exit code
    if [ "$?" -ne 0 ]; then
        cat "$tmpdir/list-$kind.err" >&2
        error "listing installed $kind failed: $*"
    fi
    # grep no-match (exit 1) は正常系。grep 自体の実行失敗 (exit >=2) と Brewfile 読取り不能のみエラー扱いする。
    if [ ! -r Brewfile ]; then
        error "Brewfile not readable"
    fi
    grep -E "^$prefix \"" Brewfile | sed "s/^$prefix \"\([^\"]*\)\".*/\1/" | normalize > "$tmpdir/brewfile-$kind"
    local drift
    drift=$(comm -23 "$tmpdir/installed-$kind" "$tmpdir/brewfile-$kind")
    if [ -n "$drift" ]; then
        warn "${kind}: installed but not in Brewfile"
        echo "$drift" | sed 's/^/  /'
        return 1
    fi
    return 0
}

rc=0
check_drift formula brew brew leaves       || rc=1
check_drift cask    cask brew list --cask  || rc=1

if [ "$rc" -eq 0 ]; then
    info "no drift (installed leaves/casks all tracked in Brewfile)"
else
    echo ""
    warn "HINT: Brewfile に追記するか、brew uninstall で削除する (make brewfile は使わない)"
fi

exit "$rc"
