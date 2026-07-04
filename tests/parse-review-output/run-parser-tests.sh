#!/usr/bin/env bash
set -euo pipefail

# parse-review-output.sh の決定的テスト。
# fixture 命名規約: <NN>-<name>.exit<0|1|2>.txt — 期待 exit code をファイル名に持つ。
# パーサの場所: claude/skills/codex-review/scripts/parse-review-output.sh
# (assets 検証時は環境変数 PARSER で上書き可能)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
PARSER="${PARSER:-$REPO_ROOT/claude/skills/codex-review/scripts/parse-review-output.sh}"

if [ ! -f "$PARSER" ]; then
  echo "ERROR: parser not found: $PARSER" >&2
  exit 1
fi

pass=0
fail=0
for f in "$SCRIPT_DIR"/*.exit[012].txt; do
  [ -f "$f" ] || { echo "ERROR: no fixtures found in $SCRIPT_DIR" >&2; exit 1; }
  base=$(basename "$f")
  want=${base##*.exit}
  want=${want%.txt}
  got=0
  bash "$PARSER" < "$f" >/dev/null 2>&1 || got=$?
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $base: expected=$want got=$got"
    fail=$((fail + 1))
  fi
done

echo "parser tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
