#!/usr/bin/env bash
set -euo pipefail

# diff (base...HEAD) から「読まずに merge してよい候補か」を判定する。
#
# 使い方: merge-gate.sh <base-branch>
# 出力 (JSON): {"verdict": "要確認|候補", "reasons": ["<rule>: <対象>", ...], "files": ["<読むべき file>", ...]}
# exit: 0 = 判定成功 (verdict がどれでも 0) / 1 = 前提エラー
#
# 「候補」は diff から見て要確認の条件に当たらなかったという意味で、no look merge 可の
# 確定ではない。未実施の検証や残した finding は diff に現れないので、/pr が evidence を
# 見て要確認へ上げる (claude/skills/pr/SKILL.md step 6)。
# tier=high の根拠は reasons に出る。files に出るのは conf の条件と削除に当たった file だけ。

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is not installed" >&2
  exit 1
fi

BASE="${1:-}"
if [ -z "$BASE" ]; then
  echo "usage: merge-gate.sh <base-branch>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
classification=$(bash "$SCRIPT_DIR/classify-risk.sh" "$BASE")

REF="$BASE"
if ! git rev-parse --verify "$BASE" >/dev/null 2>&1; then
  REF="origin/$BASE"
fi

CONF=".claude/merge-gate.conf"

reasons=""
files=""
add_reason() {
  reasons="${reasons}${reasons:+
}$1"
}
add_files() {
  files="${files}${files:+
}$1"
}

if [ "$(printf '%s' "$classification" | jq -r '.tier')" = "high" ]; then
  while IFS= read -r reason; do
    add_reason "tier-high: $reason"
  done < <(printf '%s' "$classification" | jq -r '.reasons[]')
fi

# rename を delete + add に分解する。--name-only は宛先しか返さないので、conf の対象を
# 別名へ動かすだけで条件から外れてしまう
changed=$(git -c core.quotePath=false diff "$REF...HEAD" --name-only --no-renames)
deleted=$(git -c core.quotePath=false diff "$REF...HEAD" --name-only --no-renames --diff-filter=D)

if printf '%s\n' "$changed" | grep -qxF "$CONF"; then
  add_reason "conf-change: $CONF"
  add_files "$CONF"
fi

# working tree ではなく base の版を読む。PR 自身が条件を消して「候補」になるのを防ぐ
if git cat-file -e "$REF:$CONF" 2>/dev/null; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '' | '#'*) continue ;;
      REQUIRE_REVIEW_PATH=?*) pattern="${line#REQUIRE_REVIEW_PATH=}" ;;
      *)
        echo "ERROR: $CONF: unknown line: $line" >&2
        exit 1
        ;;
    esac
    status=0
    hits=$(printf '%s\n' "$changed" | grep -iE -- "$pattern") || status=$?
    if [ "$status" -gt 1 ]; then
      echo "ERROR: $CONF: invalid pattern: $pattern" >&2
      exit 1
    fi
    if [ -n "$hits" ]; then
      add_reason "conf-path: $(printf '%s' "$hits" | tr '\n' ' ')"
      add_files "$hits"
    fi
  done < <(git show "$REF:$CONF")
fi

if [ -n "$deleted" ]; then
  add_reason "deleted: $(printf '%s' "$deleted" | tr '\n' ' ')"
  add_files "$deleted"
fi

verdict="候補"
[ -z "$reasons" ] || verdict="要確認"

jq -n --arg verdict "$verdict" --arg reasons "$reasons" --arg files "$files" '
  def lines: split("\n") | map(select(length > 0));
  {verdict: $verdict, reasons: ($reasons | lines), files: ($files | lines | unique)}'
