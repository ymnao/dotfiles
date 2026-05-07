#!/usr/bin/env bash
set -euo pipefail

# Fetch unresolved review threads for the current branch's PR

# `gh pr view` reads branch.<name>.remote from .git/config; restrictive sandboxes
# can prevent git from writing that, so fall back to lookup by branch name.
PR_NUMBER=""
if PR_JSON=$(gh pr view --json number 2>/dev/null); then
  PR_NUMBER=$(echo "$PR_JSON" | jq -r '.number // empty')
fi
if [ -z "$PR_NUMBER" ]; then
  BRANCH=$(git branch --show-current 2>/dev/null || true)
  if [ -n "$BRANCH" ]; then
    PR_NUMBER=$(gh pr list --head "$BRANCH" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)
  fi
fi
if [ -z "$PR_NUMBER" ]; then
  echo "ERROR: No PR found for the current branch" >&2
  exit 1
fi
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
