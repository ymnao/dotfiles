#!/bin/bash
set -euo pipefail

# 現在のブランチ情報をJSON形式で収集する

# 依存コマンドチェック
for cmd in gh jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd がインストールされていません" >&2
    exit 1
  fi
done

# 現在のブランチ名
BRANCH_NAME=$(git branch --show-current)

# デフォルトブランチを動的取得（フォールバック: main）
BASE_BRANCH=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || echo "main")

# mainブランチにいる場合はエラー
if [ "$BRANCH_NAME" = "$BASE_BRANCH" ]; then
  echo "ERROR: ${BASE_BRANCH}ブランチ上ではPRを作成できません。作業ブランチに切り替えてください" >&2
  exit 1
fi

# コミット一覧（ベースブランチからの差分）
COMMITS=$(git log "${BASE_BRANCH}..HEAD" --pretty=format:'{"hash":"%h","subject":"%s","body":"%b"}' | jq -s '.' 2>/dev/null || echo "[]")
COMMIT_COUNT=$(echo "$COMMITS" | jq 'length')

# diff stat
DIFF_STAT=$(git diff "${BASE_BRANCH}...HEAD" --stat 2>/dev/null || echo "")
FILES_CHANGED=$(git diff "${BASE_BRANCH}...HEAD" --numstat 2>/dev/null | wc -l | tr -d ' ')
INSERTIONS=$(git diff "${BASE_BRANCH}...HEAD" --numstat 2>/dev/null | awk '{s+=$1} END {print s+0}')
DELETIONS=$(git diff "${BASE_BRANCH}...HEAD" --numstat 2>/dev/null | awk '{s+=$1} END {print s+0}')

# リモートブランチの存在チェック
HAS_REMOTE=false
if git ls-remote --heads origin "$BRANCH_NAME" 2>/dev/null | grep -q "$BRANCH_NAME"; then
  HAS_REMOTE=true
fi

# 既存PRチェック
EXISTING_PR=$(gh pr view --json number,url,state 2>/dev/null || echo "null")
if [ "$EXISTING_PR" = "null" ] || [ -z "$EXISTING_PR" ]; then
  EXISTING_PR="null"
fi

# ブランチ名からリンクされたイシュー番号を抽出（例: feature/add-auth-#42 → 42）
LINKED_ISSUE="null"
if [[ "$BRANCH_NAME" =~ \#([0-9]+) ]]; then
  LINKED_ISSUE="${BASH_REMATCH[1]}"
fi

# JSON出力
jq -n \
  --arg branch_name "$BRANCH_NAME" \
  --arg base_branch "$BASE_BRANCH" \
  --argjson commits "$COMMITS" \
  --argjson commit_count "$COMMIT_COUNT" \
  --arg diff_stat "$DIFF_STAT" \
  --argjson files_changed "$FILES_CHANGED" \
  --argjson insertions "$INSERTIONS" \
  --argjson deletions "$DELETIONS" \
  --argjson has_remote "$HAS_REMOTE" \
  --argjson existing_pr "$EXISTING_PR" \
  --argjson linked_issue "$LINKED_ISSUE" \
  '{
    branch_name: $branch_name,
    base_branch: $base_branch,
    commits: $commits,
    commit_count: $commit_count,
    diff_stat: $diff_stat,
    files_changed: $files_changed,
    insertions: $insertions,
    deletions: $deletions,
    has_remote: $has_remote,
    existing_pr: $existing_pr,
    linked_issue: $linked_issue
  }'
