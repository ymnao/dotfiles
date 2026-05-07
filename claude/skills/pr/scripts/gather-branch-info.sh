#!/usr/bin/env bash
set -euo pipefail

# Gather current branch's git/local-file info as JSON.
# Intentionally avoids `gh`: when this script is invoked via `bash`, any nested
# `gh` becomes a grandchild of Claude Code's Bash tool and cannot resolve its
# macOS Keychain auth (token-in-keyring lookup fails). Anything that needs
# GitHub API data (default branch override, existing-PR check) is handled by
# the caller (SKILL.md) via direct `gh` invocations.

# Dependency check
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is not installed" >&2
  exit 1
fi

# Current branch name (error on detached HEAD)
BRANCH_NAME=$(git branch --show-current)
if [ -z "$BRANCH_NAME" ]; then
  echo "ERROR: Not on a branch (detached HEAD). Check out a branch first" >&2
  exit 1
fi

# Resolve default branch from local symbolic ref (set by `git clone`).
# If absent, the user can restore it with `git remote set-head origin -a`.
if ! BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null); then
  echo "ERROR: refs/remotes/origin/HEAD is not set. Run: git remote set-head origin -a" >&2
  exit 1
fi
BASE_BRANCH=${BASE_BRANCH#refs/remotes/origin/}

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
  split("") | map(select(length > 0)) |
  map(split("") | {hash: .[0], subject: .[1], body: .[2]})
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

# Extract linked issue number from branch name (e.g., feature/add-auth-#42 → 42)
LINKED_ISSUE="null"
if [[ "$BRANCH_NAME" =~ \#([0-9]+)$ ]]; then
  LINKED_ISSUE="${BASH_REMATCH[1]}"
fi

# Detect PR template
REPO_ROOT=$(git rev-parse --show-toplevel)
PR_TEMPLATE=""
for candidate in \
  "$REPO_ROOT/.github/pull_request_template.md" \
  "$REPO_ROOT/.github/PULL_REQUEST_TEMPLATE.md" \
  "$REPO_ROOT/pull_request_template.md" \
  "$REPO_ROOT/PULL_REQUEST_TEMPLATE.md" \
  "$REPO_ROOT/docs/pull_request_template.md"; do
  if [ -f "$candidate" ]; then
    PR_TEMPLATE=$(cat "$candidate")
    break
  fi
done

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
  --argjson linked_issue "$LINKED_ISSUE" \
  --arg pr_template "$PR_TEMPLATE" \
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
    linked_issue: $linked_issue,
    pr_template: (if $pr_template == "" then null else $pr_template end)
  }'
