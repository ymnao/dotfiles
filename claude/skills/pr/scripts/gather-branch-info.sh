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

# Resolve default branch.
# Prefer an explicit override from $1 (the SKILL caller queries `gh repo view`
# directly, which is authoritative even when origin/HEAD is unset or the main
# remote is not named "origin"). Fall back to refs/remotes/origin/HEAD which
# `git clone` writes by default.
if [ "${1:-}" != "" ]; then
  BASE_BRANCH="$1"
elif BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null); then
  BASE_BRANCH=${BASE_BRANCH#refs/remotes/origin/}
else
  echo "ERROR: Cannot determine default branch. Pass it as the first argument or run: git remote set-head origin -a" >&2
  exit 1
fi

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

# Commits since base branch.
# NUL is the only byte git forbids in commit messages, so it is the only
# safe inter-commit delimiter — `-z` makes git emit NUL-terminated commits.
# Pipe to jq via process substitution so the shell does not strip NULs.
COMMITS=$(jq -Rs '
  split("\u0000") | map(select(length > 0))
  | map(split("\n") as $l | {hash: $l[0], subject: $l[1], body: ($l[3:] | join("\n"))})
' < <(git log "${BASE_REF}..HEAD" -z --format='%h%n%s%n%n%b') 2>/dev/null || echo "[]")

# Diff stat (one --numstat pass for files/insertions/deletions)
DIFF_STAT=$(git diff "${BASE_REF}...HEAD" --stat 2>/dev/null || echo "")
read -r FILES_CHANGED INSERTIONS DELETIONS < <(
  git diff "${BASE_REF}...HEAD" --numstat 2>/dev/null \
    | awk '{f++; ins+=$1; del+=$2} END {printf "%d %d %d\n", f+0, ins+0, del+0}'
)

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
  --arg diff_stat "$DIFF_STAT" \
  --argjson files_changed "$FILES_CHANGED" \
  --argjson insertions "$INSERTIONS" \
  --argjson deletions "$DELETIONS" \
  --argjson linked_issue "$LINKED_ISSUE" \
  --arg pr_template "$PR_TEMPLATE" \
  '{
    branch_name: $branch_name,
    base_branch: $base_branch,
    commits: $commits,
    commit_count: ($commits | length),
    diff_stat: $diff_stat,
    files_changed: $files_changed,
    insertions: $insertions,
    deletions: $deletions,
    linked_issue: $linked_issue,
    pr_template: (if $pr_template == "" then null else $pr_template end)
  }'
