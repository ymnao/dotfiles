#!/usr/bin/env bash
#
# StopFailure hook (Claude Code 専用): API エラーでターンが終わったとき、
# エラー種別付きで macOS 通知を出す。StopFailure は Stop の代わりに発火するため、
# Stop 側の完了通知はエラー停止では鳴らない。出力と exit code は harness に無視される。

set -u

# 種別は .error から読む。docs 要約は error_type と書いていたが、2.1.282 の本体が
# 渡す入力は {error, error_details, last_assistant_message} だった (バイナリで確認)。
# error_details は通知に入れない: 自由文で AppleScript 文字列に " を注入しうるため。
# 範囲指定 a-z をロケール依存にしないため tr だけ C に固定する。
error_kind=$(jq -r '.error // empty' 2>/dev/null | LC_ALL=C tr -cd 'a-z_')
: "${error_kind:=unknown}"

osascript -e "display notification \"API エラーで停止しました (${error_kind})\" with title \"Claude Code\" sound name \"Basso\"" >/dev/null 2>&1
exit 0
