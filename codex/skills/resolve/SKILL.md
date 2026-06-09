---
name: resolve
description: Fetch and address unresolved PR review comments
---

Fetch unresolved review threads for the current PR and address each one.
Execute these steps faithfully in order. Do not skip steps or make independent judgments about the process.

## Steps

1. Determine the current branch's PR number, owner, and repo:
   - Run `gh repo view --json owner --jq '.owner.login'` → `<owner>`
   - Run `gh repo view --json name --jq '.name'` → `<repo>`
   - Run `gh pr view --json number --jq .number` (uses upstream tracking; may fail). If a number comes back, use it as `<pr_number>`.
   - Otherwise fall back: get the branch with `git branch --show-current`, then run `gh pr list --head <branch> --state open --json number,baseRefName,headRepositoryOwner --jq '[.[] | select(.headRepositoryOwner.login == "<owner>")]'`
     - 0 matches → report "No PR found for the current branch" and stop.
     - >1 matches → list `PR #<n> -> <baseRefName>` for each, ask the user which one, then proceed.
2. Fetch unresolved review threads:
   ```bash
   gh api graphql \
     -F query=@"$HOME/.codex/skills/resolve/queries/unresolved-threads.graphql" \
     -f owner=<owner> -f repo=<repo> -F number=<pr_number> \
   | jq --argjson pr_number <pr_number> '{
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
