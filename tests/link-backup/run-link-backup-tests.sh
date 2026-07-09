#!/usr/bin/env bash
set -euo pipefail

# unique_backup_path() の決定的テスト。date をシェル関数で固定タイムスタンプに
# stub し、既存 backup / 同一秒衝突 / 連続衝突の 4 分岐をカバーする。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
LIB="$REPO_ROOT/scripts/lib/backup.sh"

if [ ! -f "$LIB" ]; then
  echo "ERROR: lib not found: $LIB" >&2
  exit 1
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/link-backup.XXXXXX")"
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT

# shellcheck source=/dev/null
source "$LIB"

# date を固定タイムスタンプに stub
FIXED_TS="20260709120000"
date() { printf '%s\n' "$FIXED_TS"; }

pass=0
fail=0

assert_eq() {
  local name="$1" want="$2" got="$3"
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $name: want=$want got=$got"
    fail=$((fail + 1))
  fi
}

# case 1: backup が存在しない → $dest.backup
DEST="$WORKDIR/case1"
touch "$DEST"
got=$(unique_backup_path "$DEST")
assert_eq no-existing-backup "$DEST.backup" "$got"

# case 2: $dest.backup が既存 → $dest.backup.<ts>
DEST="$WORKDIR/case2"
touch "$DEST" "$DEST.backup"
got=$(unique_backup_path "$DEST")
assert_eq backup-exists "$DEST.backup.$FIXED_TS" "$got"

# case 3: $dest.backup + $dest.backup.<ts> が既存 → $dest.backup.<ts>.1
DEST="$WORKDIR/case3"
touch "$DEST" "$DEST.backup" "$DEST.backup.$FIXED_TS"
got=$(unique_backup_path "$DEST")
assert_eq same-second-collision "$DEST.backup.$FIXED_TS.1" "$got"

# case 4: $dest.backup + $dest.backup.<ts> + $dest.backup.<ts>.1 が既存 → $dest.backup.<ts>.2
DEST="$WORKDIR/case4"
touch "$DEST" "$DEST.backup" "$DEST.backup.$FIXED_TS" "$DEST.backup.$FIXED_TS.1"
got=$(unique_backup_path "$DEST")
assert_eq repeated-collision "$DEST.backup.$FIXED_TS.2" "$got"

# case 5: 連続 collision (n=5 まで) の loop 終端確認
DEST="$WORKDIR/case5"
touch "$DEST" "$DEST.backup" "$DEST.backup.$FIXED_TS"
for i in 1 2 3 4; do touch "$DEST.backup.$FIXED_TS.$i"; done
got=$(unique_backup_path "$DEST")
assert_eq loop-terminates "$DEST.backup.$FIXED_TS.5" "$got"

echo "link-backup tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
