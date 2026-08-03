#!/usr/bin/env bash
#
# Claude Code statusline: モデル / effort / コンテキスト使用率 / レート制限消費率
# 正本: claude/statusline.sh (settings.json の statusLine.command から参照)
#
# 入力: stdin に Claude Code が渡す JSON (https://code.claude.com/docs/en/statusline)
# 出力: 1 行のステータス文字列
# 依存: jq (無ければモデル名なしの固定文字列を出す)
#
# starship の `starship statusline claude-code` には寄せない (2026-08-04 実測、
# starship 1.26.0)。同じ JSON を渡すと eff / 5h / 7d が出ない — 1.26.0 は
# effort と rate_limits をそもそも受け取らない。得るのは git ブランチ・
# コスト・ゲージ表示。不足分を別スクリプトで補うと維持対象が 2 つに増えるので、
# 部分移行もしない。
# 再検討 trigger は「両方がリリース版に入ったら」: effort は starship#7614 が
# merge 済みで 1.27.0 予定 (ただし変数追加のみで既定 format に入らないため、
# probe するときは [claude_model] format に $effort を足す — でないと偽陰性)、
# レート制限は starship#7442 が open (CONFLICTING、2026-06 から停止)。
# starship は `brew pin` していない (Brewfile 側に版を止める記法は無い) ので
# `make update` で黙って上がり、上の 1.26.0 という測定値は古くなる。

set -uo pipefail

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  printf 'claude'
  exit 0
fi

printf '%s' "$input" | jq -r '
  [
    (.model.display_name // .model.id // "model?"),
    ("eff:" + (.effort.level // "-")),
    ("ctx:" + ((.context_window.used_percentage // 0) | round | tostring) + "%"),
    (if (.rate_limits.five_hour.used_percentage // null) != null
     then "5h:" + (.rate_limits.five_hour.used_percentage | round | tostring) + "%"
     else empty end),
    (if (.rate_limits.seven_day.used_percentage // null) != null
     then "7d:" + (.rate_limits.seven_day.used_percentage | round | tostring) + "%"
     else empty end)
  ] | join(" | ")' 2>/dev/null || printf 'claude'
