#!/bin/bash
set -euo pipefail

# イシュー情報をJSON形式で取得する

# 引数チェック
if [ $# -ne 1 ]; then
  echo "ERROR: イシュー番号を指定してください (例: fetch-issue.sh 42)" >&2
  exit 1
fi

ISSUE_NUMBER="$1"

# 数値バリデーション
if ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "ERROR: イシュー番号は数値で指定してください: $ISSUE_NUMBER" >&2
  exit 1
fi

# 依存コマンドチェック
for cmd in gh jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd がインストールされていません" >&2
    exit 1
  fi
done

# イシュー情報を取得
ISSUE_JSON=$(gh issue view "$ISSUE_NUMBER" --json number,title,body,labels,state,assignees,url 2>/dev/null) || {
  echo "ERROR: イシュー #$ISSUE_NUMBER が見つかりません" >&2
  exit 1
}

# 必要なフィールドを整形して出力
echo "$ISSUE_JSON" | jq '{
  number: .number,
  title: .title,
  body: .body,
  labels: [.labels[].name],
  state: .state,
  assignees: [.assignees[].login],
  url: .url
}'
