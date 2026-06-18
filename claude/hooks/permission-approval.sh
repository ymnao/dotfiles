#!/usr/bin/env bash
#
# Notification hook (Claude Code): スマホへ ntfy 通知を送る
#
# Phase 0 MVP — 単方向通知のみ。
# 双方向 Allow/Deny 連携 (Kohei Aoki 流 SSE 受信) は Phase 0.5 で拡張予定。
#
# 動作概要:
# - Claude Code が承認要求や注意喚起を Notification として発火したとき、
#   `~/.claude/.ntfy-topic` に保存されたランダム topic 宛に通知を投げる。
# - topic ファイルが存在しなければ silent exit (= setup-ntfy-topic.sh 未実行)。
# - curl はバックグラウンド化し、Notification 応答時間を最小化する。
#
# セットアップ:
#   bash $DOTFILES/scripts/setup-ntfy-topic.sh

set -uo pipefail

TOPIC_FILE="$HOME/.claude/.ntfy-topic"
[[ -f "$TOPIC_FILE" ]] || exit 0

NTFY_TOPIC=$(head -n 1 "$TOPIC_FILE" | tr -d '[:space:]')
[[ -n "$NTFY_TOPIC" ]] || exit 0

NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"

input=$(cat)

# jq があれば message を抽出、なければ汎用文言で送る。
if command -v jq &>/dev/null; then
  message=$(printf '%s' "$input" \
    | jq -r '.message // .reason // "操作の確認が必要です"' 2>/dev/null)
else
  message="Claude Code から通知"
fi

project=$(basename "${PWD:-/}")

curl -fsSL \
  -H "Title: Claude Code [$project]" \
  -H "Priority: high" \
  -H "Tags: bell,computer" \
  -d "$message" \
  "$NTFY_SERVER/$NTFY_TOPIC" >/dev/null 2>&1 &

exit 0
