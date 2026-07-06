#!/usr/bin/env bash
set -uo pipefail

# statusline.sh の出力テスト。fixtures/*.json を流し、同名 .expected と比較する。
#
# 使い方: run-statusline-tests.sh
#   環境変数 SCRIPT_PATH で statusline スクリプトの場所を上書きできる
#   (デフォルト: <リポジトリルート>/claude/statusline.sh)
#
# 依存: bash 3.2+ / jq

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
TARGET="${SCRIPT_PATH:-$REPO_ROOT/claude/statusline.sh}"

if [ ! -f "$TARGET" ]; then
  echo "ERROR: statusline script not found: $TARGET (SCRIPT_PATH で上書き可)" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }

pass=0
fail=0

for fixture in "$SCRIPT_DIR"/fixtures/*.json; do
  [ -f "$fixture" ] || { echo "ERROR: no fixtures found" >&2; exit 1; }
  name=$(basename "$fixture" .json)
  expected_file="${fixture%.json}.expected"
  if [ ! -f "$expected_file" ]; then
    echo "FAIL $name: expected ファイルがない ($expected_file)"
    fail=$((fail + 1))
    continue
  fi
  got=$(bash "$TARGET" <"$fixture")
  rc=$?
  expected=$(cat "$expected_file")
  if [ "$rc" = 0 ] && [ "$got" = "$expected" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $name: rc=$rc"
    echo "  expected: $expected"
    echo "  got:      $got"
    fail=$((fail + 1))
  fi
done

echo "----"
echo "statusline tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
