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

# 設定ファイル形式 (setup-ntfy-topic.sh が生成):
#   server=<https://ntfy.sh or self-host>
#   topic=<random topic>
# シェル source ではなく grep/cut で読むことで、設定ファイル経由の任意コード
# 実行を防ぐ。
CONFIG_FILE="$HOME/.claude/.ntfy-config"
[[ -f "$CONFIG_FILE" ]] || exit 0

NTFY_TOPIC=$(grep -E '^topic=' "$CONFIG_FILE" | head -n 1 | cut -d= -f2-)
NTFY_SERVER=$(grep -E '^server=' "$CONFIG_FILE" | head -n 1 | cut -d= -f2-)
[[ -n "$NTFY_TOPIC" ]] || exit 0
# server 未保存時 (旧形式の救済) はパブリック ntfy.sh にフォールバック。
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"

input=$(cat)

# jq があれば message を抽出、なければ汎用文言で送る。
if command -v jq &>/dev/null; then
  message=$(printf '%s' "$input" \
    | jq -r '.message // .reason // "操作の確認が必要です"' 2>/dev/null)
else
  message="Claude Code から通知"
fi

# Phase 0 はパブリック ntfy.sh を経由するが、承認待ち通知の信頼性を優先する:
#   - Title はプロジェクト名なしの固定文言にして機密情報の流出を最小化。
#   - サーバキャッシュ (12h) は有効のまま。F-Droid 版 ntfy アプリのように
#     FCM を使わないクライアントや、Android のプロセス停止・回線断からの
#     再接続時にも、承認待ち通知を取りこぼさないため。
#   - FCM/APNs 経由 (Firebase header デフォルト) も有効。Firebase: no を
#     付けると Android/iOS で実質受信不能になるため使わない。
# Phase 1 でセルフホストか認証付き topic に移行して FCM 依存とサーバ残留の
# 両方を解消する予定。
curl -fsSL \
  --connect-timeout 3 \
  --max-time 8 \
  -H "Title: Claude Code" \
  -H "Priority: high" \
  -H "Tags: bell,computer" \
  --data-raw "$message" \
  "$NTFY_SERVER/$NTFY_TOPIC" >/dev/null 2>&1

exit 0
