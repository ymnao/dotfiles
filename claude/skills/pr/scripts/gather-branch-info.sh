#!/usr/bin/env bash
set -euo pipefail

# Gather current branch information in JSON format

# Dependency check
for cmd in gh jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd is not installed" >&2
    exit 1
  fi
done

# Current branch name (error on detached HEAD)
BRANCH_NAME=$(git branch --show-current)
if [ -z "$BRANCH_NAME" ]; then
  echo "ERROR: Not on a branch (detached HEAD). Check out a branch first" >&2
  exit 1
fi

# Resolve default branch: GitHub CLI → local symbolic ref → error
resolve_default_branch() {
  local branch

  if branch=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null) && [ -n "$branch" ]; then
    echo "$branch"
    return 0
  fi

  if branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null); then
    branch=${branch#refs/remotes/origin/}
    if [ -n "$branch" ]; then
      echo "$branch"
      return 0
    fi
  fi

  echo "ERROR: Failed to determine default branch" >&2
  exit 1
}

BASE_BRANCH=$(resolve_default_branch)

# Resolve base branch ref (prefer local, fallback to origin/)
BASE_REF="$BASE_BRANCH"
if ! git rev-parse --verify "$BASE_BRANCH" &>/dev/null; then
  if git rev-parse --verify "origin/$BASE_BRANCH" &>/dev/null; then
    BASE_REF="origin/$BASE_BRANCH"
  else
    echo "ERROR: Base branch '$BASE_BRANCH' not found locally or on remote. Run: git fetch origin $BASE_BRANCH" >&2
    exit 1
  fi
fi

# Error if on the default branch
if [ "$BRANCH_NAME" = "$BASE_BRANCH" ]; then
  echo "ERROR: Cannot create PR from ${BASE_BRANCH} branch. Switch to a feature branch first" >&2
  exit 1
fi

# Commits since base branch
COMMITS=$(git log "${BASE_REF}..HEAD" --pretty=format:"%h%x1f%s%x1f%b%x1e" | jq -Rs '
  split("\u001e") | map(select(length > 0)) |
  map(split("\u001f") | {hash: .[0], subject: .[1], body: .[2]})
' 2>/dev/null || echo "[]")
COMMIT_COUNT=$(echo "$COMMITS" | jq 'length')

# Diff stat
DIFF_STAT=$(git diff "${BASE_REF}...HEAD" --stat 2>/dev/null || echo "")
FILES_CHANGED=$(git diff "${BASE_REF}...HEAD" --numstat 2>/dev/null | wc -l | tr -d ' ')
INSERTIONS=$(git diff "${BASE_REF}...HEAD" --numstat 2>/dev/null | awk '{s+=$1} END {print s+0}')
DELETIONS=$(git diff "${BASE_REF}...HEAD" --numstat 2>/dev/null | awk '{s+=$2} END {print s+0}')

# Check if remote branch exists
HAS_REMOTE=false
if git ls-remote --heads origin "$BRANCH_NAME" 2>/dev/null | grep -q "$BRANCH_NAME"; then
  HAS_REMOTE=true
fi

# Check for existing PR
EXISTING_PR=$(gh pr view --json number,url,state 2>/dev/null || echo "null")
if [ "$EXISTING_PR" = "null" ] || [ -z "$EXISTING_PR" ]; then
  EXISTING_PR="null"
fi

# Extract linked issue number from branch name (e.g., feature/add-auth-#42 → 42)
LINKED_ISSUE="null"
if [[ "$BRANCH_NAME" =~ \#([0-9]+)$ ]]; then
  LINKED_ISSUE="${BASH_REMATCH[1]}"
fi

# JSON output
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
