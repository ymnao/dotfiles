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

BASE="${1:-}"
if [ -z "$BASE" ]; then
  echo "usage: merge-gate.sh <base-branch>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# jq が無い・base が見つからないときは、ここで classify-risk.sh が exit 1 で止まる
classification=$(bash "$SCRIPT_DIR/classify-risk.sh" "$BASE")

REF="$BASE"
if ! git rev-parse --verify "$BASE" >/dev/null 2>&1; then
  REF="origin/$BASE"
fi

CONF=".claude/merge-gate.conf"

# rename を delete + add に分解する。--name-only は宛先しか返さないので、conf の対象を
# 別名へ動かすだけで条件から外れてしまう
changed=$(git -c core.quotePath=false diff "$REF...HEAD" --name-only --no-renames)
deleted=$(git -c core.quotePath=false diff "$REF...HEAD" --name-only --no-renames --diff-filter=D)

reasons=$(printf '%s' "$classification" | jq -r 'select(.tier == "high") | .reasons[] | "tier-high: \(.)"')
files=""
add_hit() {
  reasons="$reasons
$1: $(printf '%s' "$2" | tr '\n' ' ')"
  files="$files
$2"
}

# tier=high の reasons は対象を切り詰め、内容ルールでは file 名を持たないので diff 全体を読む対象にする
if [ -n "$reasons" ]; then
  files="$changed"
fi

# grep -q は一致した時点で閉じる。pipefail の下だと長い一覧で printf が SIGPIPE になり、一致を不一致と読む
if printf '%s\n' "$changed" | grep -xF "$CONF" >/dev/null; then
  add_hit "conf-change" "$CONF"
fi

# working tree ではなく base の版を読む。PR 自身が条件を消して「候補」になるのを防ぐ。
# cat-file -e は取得の失敗も「無い」と同じ終了コードにするので使わない (理由は run-review.sh)
if git rev-parse -q --verify "$REF:$CONF" >/dev/null; then
  conf_text=$(git show "$REF:$CONF")
  while IFS= read -r line; do
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
      add_hit "conf-path" "$hits"
    fi
  done < <(printf '%s\n' "$conf_text")
fi

if [ -n "$deleted" ]; then
  add_hit "deleted" "$deleted"
fi

verdict="候補"
[ -z "$reasons" ] || verdict="要確認"

jq -n --arg verdict "$verdict" --arg reasons "$reasons" --arg files "$files" '
  def lines: split("\n") | map(select(length > 0));
  {verdict: $verdict, reasons: ($reasons | lines), files: ($files | lines | unique)}'
