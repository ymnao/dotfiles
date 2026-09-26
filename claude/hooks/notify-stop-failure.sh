#!/usr/bin/env bash
#
# StopFailure hook (Claude Code 専用): API エラーでターンが終わったとき、
# error_type 付きで macOS 通知を出す。StopFailure は Stop の代わりに発火するため、
# Stop 側の完了通知はエラー停止では鳴らない。出力と exit code は harness に無視される。

set -u

# error_message は通知に入れない: 自由文で AppleScript 文字列に " を注入しうるため。
# error_type は閉じた enum なので文字種を絞るだけで足りる。
error_type=$(jq -r '.error_type // empty' 2>/dev/null | tr -cd 'a-z_')
: "${error_type:=unknown}"

osascript -e "display notification \"API エラーで停止しました (${error_type})\" with title \"Claude Code\" sound name \"Basso\"" >/dev/null 2>&1
exit 0
