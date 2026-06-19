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
# - 起動側 (settings.json) で "async": true を指定し、Claude Code の hook
#   機構が背景実行を管理する (本スクリプト側で & を付けない)。
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

# Phase 0 はパブリック ntfy.sh を経由するため、サーバ側に残る情報は最小化する。
#   - Title からプロジェクト名を外す (現在地が機密リポでも漏れない)。
#   - Cache: no で 12 時間のサーバキャッシュを無効化 (取りこぼしリスクと
#     トレードオフ)。
# FCM/APNs 経由 (= ntfy のデフォルトの Firebase header) は端末への通知配送に
# 必須のため有効のまま (Firebase: no を付けると Android/iOS で実質受信不能)。
# Phase 1 でセルフホストか認証付き topic に移行して FCM 依存を解く予定。
curl -fsSL \
  --connect-timeout 3 \
  --max-time 8 \
  -H "Title: Claude Code" \
  -H "Priority: high" \
  -H "Tags: bell,computer" \
  -H "Cache: no" \
  --data-raw "$message" \
  "$NTFY_SERVER/$NTFY_TOPIC" >/dev/null 2>&1

exit 0
