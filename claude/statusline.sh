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
# starship 1.26.0)。同じ JSON を渡すと eff / 5h / 7d が出ない (claude 系は
# claude_model / claude_context / claude_cost の 3 モジュールのみ)。得るのは
# git ブランチ・コスト・ゲージ表示。不足分を別スクリプトで補うと維持対象が
# 2 つに増えて逆効果なので、部分移行もしない。
# 再検討 trigger: effort は starship#7614 が 2026-07-26 に merge 済み (次
# リリースで入る)、レート制限は starship#7442 が open。両方入ったら再検討する。
# Brewfile は starship を pin していないので `make update` で黙って上がる。

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
