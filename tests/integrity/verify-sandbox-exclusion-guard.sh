#!/usr/bin/env bash
#
# guard-sandbox-exclusions.sh (issue #267) が「実際に効いている除外リスト」と
# ずれていないこと、および PreToolUse に配線されていることを検証する。
#
# なぜ必要か: hook の回帰テスト (tests/hooks/guard-sandbox-exclusions.cases.jsonl)
# は隔離 HOME で走るため、hook 内の組み込み既定リスト (builtin_globs) だけを
# 通る。したがって claude/settings.json の .sandbox.excludedCommands に項目が
# 増えても、テストは古いリストに対して green を返し続ける (vacuous pass)。
# 同じ理由で、PreToolUse から hook を外しても hook テストは green のままになる。
# どちらも「守っているつもりで守っていない」状態なので、ここで assert する。
#
# 依存: bash 3.2+ / jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
SETTINGS="${INTEGRITY_SETTINGS:-$REPO_ROOT/claude/settings.json}"
HOOK="${INTEGRITY_EXCLUSION_HOOK:-$REPO_ROOT/claude/hooks/guard-sandbox-exclusions.sh}"

pass=0
fail=0

if [ ! -f "$HOOK" ]; then
  echo "FAIL: hook が見つからない: $HOOK"
  echo "sandbox exclusion guard: 0 passed, 1 failed"
  exit 1
fi

# 1. PreToolUse (Bash) に配線されているか
if jq -e '
      [.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]?.command]
      | any(. | test("guard-sandbox-exclusions\\.sh"))
    ' "$SETTINGS" >/dev/null; then
  pass=$((pass + 1))
else
  echo "FAIL: claude/settings.json: PreToolUse (Bash) に guard-sandbox-exclusions.sh の配線が無い"
  fail=$((fail + 1))
fi

# 2. hook の組み込み既定リストが settings の excludedCommands を網羅しているか。
#    hook 側の配列リテラルをそのまま取り出して評価する (hook 全体は source しない
#    — stdin 読み込みで固まるため)。
builtin_line=$(grep -m1 '^builtin_globs=(' "$HOOK" || true)
if [ -z "$builtin_line" ]; then
  echo "FAIL: $HOOK に builtin_globs=( の行が無い (リネームされた?)"
  fail=$((fail + 1))
else
  builtin_globs=()
  eval "$builtin_line"
  while IFS= read -r want; do
    [ -n "$want" ] || continue
    found=0
    for g in "${builtin_globs[@]}"; do
      if [ "$g" = "$want" ]; then
        found=1
        break
      fi
    done
    if [ "$found" = 1 ]; then
      pass=$((pass + 1))
    else
      echo "FAIL: excludedCommands の '$want' が guard-sandbox-exclusions.sh の builtin_globs に無い"
      echo "      (hook テストは隔離 HOME で builtin_globs しか通らないため、この項目は未検証のまま green になる)"
      fail=$((fail + 1))
    fi
  done < <(jq -r '.sandbox.excludedCommands // [] | .[]' "$SETTINGS")
fi

echo "sandbox exclusion guard: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
