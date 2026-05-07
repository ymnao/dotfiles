#!/usr/bin/env bash
set -euo pipefail

# Fetch unresolved review threads for the current branch's PR

# `gh pr view` reads branch.<name>.remote from .git/config; restrictive sandboxes
# can prevent git from writing that, so fall back to lookup by branch name.
# The fallback scopes by headRepositoryOwner to avoid matching same-named
# branches from forks or other users.
PR_NUMBER=""
if PR_JSON=$(gh pr view --json number 2>/dev/null); then
  PR_NUMBER=$(echo "$PR_JSON" | jq -r '.number // empty')
fi
REPO_INFO=$(gh repo view --json owner,name)
OWNER=$(echo "$REPO_INFO" | jq -r '.owner.login')
REPO=$(echo "$REPO_INFO" | jq -r '.name')
if [ -z "$PR_NUMBER" ]; then
  BRANCH=$(git branch --show-current 2>/dev/null || true)
  if [ -n "$BRANCH" ]; then
    PR_CANDIDATES=$(gh pr list --head "$BRANCH" --state open --json number,baseRefName,headRepositoryOwner \
      --jq "[.[] | select(.headRepositoryOwner.login == \"$OWNER\")]" 2>/dev/null || true)
    if [ -z "$PR_CANDIDATES" ]; then PR_CANDIDATES="[]"; fi
    PR_COUNT=$(echo "$PR_CANDIDATES" | jq 'length')
    if [ "$PR_COUNT" = "1" ]; then
      PR_NUMBER=$(echo "$PR_CANDIDATES" | jq -r '.[0].number')
    elif [ "$PR_COUNT" -gt 1 ]; then
      echo "ERROR: Multiple open PRs found for branch '$BRANCH' (cannot disambiguate without upstream tracking):" >&2
      echo "$PR_CANDIDATES" | jq -r '.[] | "  PR #\(.number) -> \(.baseRefName)"' >&2
      exit 1
    fi
  fi
fi
if [ -z "$PR_NUMBER" ]; then
  echo "ERROR: No PR found for the current branch" >&2
  exit 1
fi

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
