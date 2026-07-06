#!/usr/bin/env bash
#
# Claude Code statusline: モデル / effort / コンテキスト使用率 / レート制限消費率
# 正本: claude/statusline.sh (settings.json の statusLine.command から参照)
#
# 入力: stdin に Claude Code が渡す JSON (https://code.claude.com/docs/en/statusline)
# 出力: 1 行のステータス文字列
# 依存: jq (無ければモデル名なしの固定文字列を出す)

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
