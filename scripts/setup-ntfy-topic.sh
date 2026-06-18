#!/usr/bin/env bash
#
# ntfy topic を生成して `~/.claude/.ntfy-topic` に保存する。
# Phase 0 セットアップ用。一度だけ実行する想定。
#
# topic 名はパブリック ntfy.sh での「共有秘密」になるため、推測困難なランダム
# 文字列を base64 から生成する。ファイルは 600 (本人のみ読書可)。
#
# 使い方:
#   bash scripts/setup-ntfy-topic.sh
#
# Re-run すると上書き確認プロンプトが出る。

set -euo pipefail

TOPIC_FILE="$HOME/.claude/.ntfy-topic"
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"

if [[ -f "$TOPIC_FILE" ]]; then
  existing=$(head -n 1 "$TOPIC_FILE" | tr -d '[:space:]')
  printf '既存 topic を検出: %s (file: %s)\n' "$existing" "$TOPIC_FILE"
  printf '上書きしますか? [y/N] '
  read -r yn
  case "$yn" in
    [Yy]*) ;;
    *) echo "中止しました"; exit 0;;
  esac
fi

# URL safe な 16 文字を /dev/urandom から作る。+/= は除去し、小文字化。
random_suffix=$(head -c 24 /dev/urandom | base64 | tr -d '+/=' | tr 'A-Z' 'a-z' | head -c 16)
random_topic="claude-${random_suffix}"

mkdir -p "$(dirname "$TOPIC_FILE")"
# umask で作成時点から 0600 にする。通常の umask 0022 では書き込み前に短時間
# 0644 で晒される窓ができるため、chmod 600 では不十分。chmod は明示として併用。
umask 077
printf '%s\n' "$random_topic" > "$TOPIC_FILE"
chmod 600 "$TOPIC_FILE"

cat <<EOF

topic を生成しました
  topic:  $random_topic
  server: $NTFY_SERVER
  file:   $TOPIC_FILE (chmod 600)

==== 次のステップ ====
1. スマホに ntfy アプリをインストール
   iOS:     https://apps.apple.com/app/ntfy/id1625396347
   Android: https://f-droid.org/packages/io.heckel.ntfy/

2. ntfy アプリで以下を購読
   server: $NTFY_SERVER
   topic:  $random_topic

3. テスト送信 (Mac 側で実行)
   curl -d 'Hello from Mac' $NTFY_SERVER/$random_topic
EOF
