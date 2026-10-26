#!/usr/bin/env bash
#
# 宣言されていないインストール済みパッケージを検出する。
#   - brew の formula leaves と cask: Brewfile の brew / cask 行と突き合わせる
#   - uv / cargo の global install: Brewfile の uv / cargo 行と突き合わせる
#   - pnpm の global install: 宣言先を持たない (0 件が正) ので、あれば全部 drift
#
# `make update` が既に Brewfile → installed 方向 (brew bundle check) を担当するので、
# ここは installed → Brewfile 方向 (未追跡 drift) 専用。
# `brew bundle dump` は Brewfile 手動編集の構造 (セクション・コメント・trusted:) を
# 破壊するため使わない (CLAUDE.md 参照)。uv / cargo の一覧も `brew bundle dump --uv`
# 等からは取らない。brew 側が一覧コマンドの失敗を空の一覧として扱い、取得に
# 失敗しても drift なしと出るため。
#
# tap 付き記述 (例: "supabase/tap/supabase") は最終 / 以降で正規化して突き合わせる。
#
# `uv tool list` と `cargo install --list` は agent の sandbox 内では
# Operation not permitted で失敗する (2026-10-27 実測)。そのときは drift なしではなく
# エラーで止まる。user の shell から実行する前提。

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

# npm の scope 付き名 (@scope/name) は / を含むが tap 記述ではないので、最終要素に削らない。
normalize() { awk -F/ '/^@/ {print; next} {print $NF}' | sort; }

list_uv()    { uv tool list | awk '/^[A-Za-z0-9][^ ]* v/ {print $1}'; }
list_cargo() { cargo install --list | awk '/^[^ \t]/ {print $1}'; }
list_pnpm() {
    command -v jq >/dev/null || { echo "jq not installed" >&2; return 1; }
    pnpm ls -g --depth=0 --json | jq -r '.[] | (.dependencies // {}) | keys[]'
}

# $1: kind label (formula|cask|uv|cargo|pnpm)
# $2: Brewfile 側の prefix。空なら宣言 0 件として扱う
# $3..: installed 側の listing コマンド
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
    if [ -n "$prefix" ]; then
        # grep no-match (exit 1) は正常系。grep 自体の実行失敗 (exit >=2) と Brewfile 読取り不能のみエラー扱いする。
        if [ ! -r Brewfile ]; then
            error "Brewfile not readable"
        fi
        grep -E "^$prefix \"" Brewfile | sed "s/^$prefix \"\([^\"]*\)\".*/\1/" | normalize > "$tmpdir/declared-$kind"
    else
        : > "$tmpdir/declared-$kind"
    fi
    local drift
    drift=$(comm -23 "$tmpdir/installed-$kind" "$tmpdir/declared-$kind")
    if [ -n "$drift" ]; then
        if [ -n "$prefix" ]; then
            warn "${kind}: installed but not in Brewfile"
        else
            warn "${kind}: global install found (none is expected)"
        fi
        echo "$drift" | sed 's/^/  /'
        return 1
    fi
    return 0
}

# $1: ツール名 (kind label を兼ねる。入っていなければ skip)、$2: Brewfile 側の prefix、$3: listing 関数
check_global() {
    if ! command -v "$1" >/dev/null; then
        skip "$1 not installed"
        return 0
    fi
    check_drift "$1" "$2" "$3"
}

rc=0
check_drift formula brew brew leaves       || rc=1
check_drift cask    cask brew list --cask  || rc=1
check_global uv    uv    list_uv           || rc=1
check_global cargo cargo list_cargo        || rc=1
check_global pnpm  ""    list_pnpm         || rc=1

if [ "$rc" -eq 0 ]; then
    info "no drift (brew leaves/casks and uv/cargo/pnpm globals all declared)"
else
    echo ""
    warn "HINT: brew / uv / cargo は Brewfile に追記するか、各ツールの uninstall で削除する (make brewfile は使わない)。pnpm の global は pnpm remove -g で削除する"
fi

exit "$rc"
