---
name: resolve
description: Fetch and address unresolved PR review comments
disable-model-invocation: true
---

Fetch unresolved review threads for the current PR and address each one.

## Steps

1. Determine the current branch's PR number, owner, and repo (run each as a direct `gh` invocation):
   - `OWNER=$(gh repo view --json owner --jq '.owner.login')`
   - `REPO=$(gh repo view --json name --jq '.name')`
   - Try `PR_NUMBER=$(gh pr view --json number --jq .number 2>/dev/null)` — uses upstream tracking. If a number comes back, use it.
   - Otherwise fall back: `BRANCH=$(git branch --show-current)` then `gh pr list --head "$BRANCH" --state open --json number,baseRefName,headRepositoryOwner --jq "[.[] | select(.headRepositoryOwner.login == \"$OWNER\")]"`.
     - 0 matches → report "No PR found for the current branch" and stop.
     - >1 matches → list `PR #<n> -> <baseRefName>` for each, ask the user which one, then proceed.
2. Fetch unresolved review threads in one shell command (gh + jq are direct children — keychain-safe):
   ```bash
   gh api graphql \
     -F query=@"$HOME/.claude/skills/resolve/queries/unresolved-threads.graphql" \
     -f owner="$OWNER" -f repo="$REPO" -F number="$PR_NUMBER" \
   | jq --argjson pr_number "$PR_NUMBER" '{
       pr_number: $pr_number,
       unresolved_threads: [
         .data.repository.pullRequest.reviewThreads.nodes[]
         | select(.isResolved == false)
         | { path, line, comments: [.comments.nodes[] | {author: .author.login, body, createdAt}] }
       ]
     }'
   ```
3. If `unresolved_threads` is empty, report that there are no unresolved comments and stop
4. For each thread:
   - Read the relevant file and line to understand the current state
   - Evaluate whether the suggestion is valid
   - If valid, fix the code (apply best practices regardless of effort)
   - If unnecessary or inappropriate, prepare a clear reason
5. If any fixes were made, run all applicable verification steps for the project:
   - Lint / static analysis
   - Format check
   - Type check
   - Build
   - Unit tests
   - Integration tests
   - E2E tests
   - Determine available commands from package.json, Makefile, pyproject.toml, Cargo.toml, etc.
6. Commit and push
7. Report all results in the format below

## Report format

| # | Comment | Action | Reason |
|---|---------|--------|--------|
| 1 | ... | Fixed (commit hash) | ... |
| 2 | ... | Won't fix | ... |
