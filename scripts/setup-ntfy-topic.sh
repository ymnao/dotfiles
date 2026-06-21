#!/usr/bin/env bash
#
# ntfy 通知用の設定 (server と topic) を生成して `~/.claude/.ntfy-config` に
# 保存する。Phase 0 セットアップ用、一度だけ実行する想定。
#
# topic 名はパブリック ntfy.sh での「共有秘密」になるため、推測困難なランダム
# 文字列を base64 から生成する。ファイルは 0600 (本人のみ読書可)。
#
# 設定ファイルの形式は 1 行 1 key=value (シェル source ではなく grep/cut で
# 読む形式に統一して、任意コード実行リスクを避ける):
#   server=https://ntfy.sh
#   topic=claude-xxxx
#
# 使い方:
#   bash scripts/setup-ntfy-topic.sh
#
# Re-run すると上書き確認プロンプトが出る。
# NTFY_SERVER 環境変数で別サーバ (セルフホスト等) を指定可能。

set -euo pipefail

CONFIG_FILE="$HOME/.claude/.ntfy-config"
# 末尾スラッシュを除去して正規化 (purl join 時のダブルスラッシュ防止)。
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
NTFY_SERVER="${NTFY_SERVER%/}"

if [[ -f "$CONFIG_FILE" ]]; then
  # set -euo pipefail 下で grep が空マッチすると pipeline exit 1 でスクリプトが
  # 落ちる。手で .ntfy-config を編集して片方のキーだけ消えた状態でも上書き
  # 確認まで進めるように、欠損を許容する。
  existing_topic=$(grep -E '^topic=' "$CONFIG_FILE" | head -n 1 | cut -d= -f2-) || true
  existing_server=$(grep -E '^server=' "$CONFIG_FILE" | head -n 1 | cut -d= -f2-) || true
  printf '既存設定を検出: %s\n' "$CONFIG_FILE"
  printf '  server: %s\n' "${existing_server:-(未保存、ntfy.sh)}"
  printf '  topic:  %s\n' "$existing_topic"
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

mkdir -p "$(dirname "$CONFIG_FILE")"
# umask で作成時点から 0600 にする。通常の umask 0022 では書き込み前に短時間
# 0644 で晒される窓ができるため、chmod 600 では不十分。chmod は明示として併用。
umask 077
{
  printf 'server=%s\n' "$NTFY_SERVER"
  printf 'topic=%s\n' "$random_topic"
} > "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

cat <<EOF

設定を生成しました
  server: $NTFY_SERVER
  topic:  $random_topic
  file:   $CONFIG_FILE (chmod 600)

==== 次のステップ ====
1. スマホに ntfy アプリをインストール
   iOS:     https://apps.apple.com/app/ntfy/id1625396347
   Android: https://f-droid.org/packages/io.heckel.ntfy/

2. ntfy アプリで上記の server / topic を購読

3. テスト送信 (Mac 側で実行)
   curl -d 'Hello from Mac' $NTFY_SERVER/$random_topic
EOF
