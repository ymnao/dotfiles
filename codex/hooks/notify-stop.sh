#!/usr/bin/env bash
#
# Stop hook (Codex CLI): タスク完了時にデスクトップ通知を送る
# macOS は osascript、Linux は notify-send にフォールバック
#

case "$(uname -s)" in
  Darwin)
    osascript -e 'display notification "タスクが完了しました" with title "Codex CLI" sound name "Glass"' 2>/dev/null
    ;;
  Linux)
    if command -v notify-send &>/dev/null; then
      notify-send "Codex CLI" "タスクが完了しました" 2>/dev/null
    fi
    ;;
esac

exit 0
