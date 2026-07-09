# shellcheck shell=bash
#
# backup.sh — 上書き回避付きバックアップパス生成
# Source-only。既存 backup を壊さないユニークなパスを stdout に返す。
#
# 命名規則:
#   1. $dest.backup           (未使用ならこれ)
#   2. $dest.backup.<ts>      (.backup 既存時、ts = YYYYMMDDHHMMSS)
#   3. $dest.backup.<ts>.<n>  (同一秒で衝突した場合、n を 1 から incr)
#
# Usage:
#   backup_path=$(unique_backup_path "/path/to/file")

# -e / -L 併用: 壊れた symlink (-e が false になる) も「衝突」扱いにする
unique_backup_path() {
    local dest="$1"
    local backup="$dest.backup"
    if [[ ! -e "$backup" && ! -L "$backup" ]]; then
        printf '%s' "$backup"
        return
    fi
    local ts
    ts=$(date +%Y%m%d%H%M%S)
    backup="$dest.backup.$ts"
    local i=1
    while [[ -e "$backup" || -L "$backup" ]]; do
        backup="$dest.backup.$ts.$i"
        i=$((i + 1))
    done
    printf '%s' "$backup"
}
