#!/usr/bin/env bash
set -euo pipefail

# Fetch unresolved review threads for the current branch's PR

PR_JSON=$(gh pr view --json number,url 2>/dev/null) || {
  echo "ERROR: No PR found for the current branch" >&2
  exit 1
}

PR_NUMBER=$(echo "$PR_JSON" | jq -r '.number')
REPO_INFO=$(gh repo view --json owner,name)
OWNER=$(echo "$REPO_INFO" | jq -r '.owner.login')
REPO=$(echo "$REPO_INFO" | jq -r '.name')

RESULT=$(gh api graphql -f query='
  query($owner: String!, $repo: String!, $number: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $number) {
        reviewThreads(first: 100) {
          nodes {
            isResolved
            path
            line
            comments(first: 10) {
              nodes {
                body
                author { login }
                createdAt
              }
            }
          }
        }
      }
    }
  }
' -f owner="$OWNER" -f repo="$REPO" -F number="$PR_NUMBER")

# Extract only unresolved threads
echo "$RESULT" | jq '{
  pr_number: '"$PR_NUMBER"',
  unresolved_threads: [
    .data.repository.pullRequest.reviewThreads.nodes[]
    | select(.isResolved == false)
    | {
        path: .path,
        line: .line,
        comments: [.comments.nodes[] | {author: .author.login, body: .body, createdAt: .createdAt}]
      }
  ]
}'
