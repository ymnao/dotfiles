#!/bin/bash
set -euo pipefail

# Fetch issue information in JSON format

# Argument check
if [ $# -ne 1 ]; then
  echo "ERROR: Issue number required (e.g., fetch-issue.sh 42)" >&2
  exit 1
fi

ISSUE_NUMBER="$1"

# Numeric validation
if ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "ERROR: Issue number must be numeric: $ISSUE_NUMBER" >&2
  exit 1
fi

# Dependency check
for cmd in gh jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd is not installed" >&2
    exit 1
  fi
done

# Fetch issue info
ISSUE_JSON=$(gh issue view "$ISSUE_NUMBER" --json number,title,body,labels,state,assignees,url 2>/dev/null) || {
  echo "ERROR: Issue #$ISSUE_NUMBER not found" >&2
  exit 1
}

# Format and output
echo "$ISSUE_JSON" | jq '{
  number: .number,
  title: .title,
  body: .body,
  labels: [.labels[].name],
  state: .state,
  assignees: [.assignees[].login],
  url: .url
}'
