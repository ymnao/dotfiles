---
name: resolve
description: Fetch and address unresolved PR review comments
disable-model-invocation: true
---

Fetch unresolved review threads for the current PR and address each one.

## Steps

1. Determine the current branch's PR number, owner, and repo. Run each `gh` command as a bare invocation and substitute the prior output literally into the next call (no `VAR=$(...)` — the permission allow-list matches by command prefix, which command-substitution wrapping breaks):
   - Run `gh repo view --json owner --jq '.owner.login'` → `<owner>`
   - Run `gh repo view --json name --jq '.name'` → `<repo>`
   - Run `gh pr view --json number --jq .number` (uses upstream tracking; may fail). If a number comes back, use it as `<pr_number>`.
   - Otherwise fall back: get the branch with `git branch --show-current`, then run `gh pr list --state open --limit 100 --json number,baseRefName,headRefName,headRepositoryOwner` as a bare invocation and read the output, keeping the rows whose `headRefName` equals that branch and whose `headRepositoryOwner.login` equals `<owner>`. **Do not substitute the branch name into the command** — ref names may contain `$(...)` or `;` (`git check-ref-format --branch 'foo$(id);x'` exits 0) and this repo is public, so an issue title can reach a branch name via `/issue`; quoting does not stop `$(...)` from expanding. Matching on the output side keeps the name out of the command string (and keeps `gh` a bare invocation). `--limit` is spelled out because `gh pr list` defaults to 30 rows, and a repo with more open PRs than that would silently report "No PR found".
     - 0 matches → report "No PR found for the current branch" and stop.
     - >1 matches → list `PR #<n> -> <baseRefName>` for each, ask the user which one, then proceed.
2. Fetch unresolved review threads in one Bash invocation containing **only** `gh api graphql ...` — no pipe, no `&&`, no second command (the leading command must be `gh api graphql` for the allow-list to match, and mixing any other command in the same invocation is blocked by `guard-sandbox-exclusions.sh`; see issue #267). Use `gh`'s built-in `--jq` instead of piping to `jq`, and substitute `<owner>`, `<repo>`, `<pr_number>` literally from step 1.
   The query is inlined rather than read with `-F query=@"$HOME/.../unresolved-threads.graphql"`: that `"$HOME/..."` combined with the `{` in `--jq` failed with `tls: failed to verify certificate: x509: OSStatus -26276` every time (issue #359, measured 2026-09-25; either one alone succeeded). The likely cause is that the call stops matching the `gh *` sandbox exclusion, but the matching rule itself is unverified. Do not reintroduce `$HOME` or other variable expansion here. The query stays on one line because `block-dangerous-commands.sh` blocks a continuation line that starts with a word containing `$` (e.g. `repository(owner: $owner, ...`) as a dynamically built command name:
   ```bash
   gh api graphql \
     -f query='query($owner: String!, $repo: String!, $number: Int!) { repository(owner: $owner, name: $repo) { pullRequest(number: $number) { reviewThreads(first: 100) { nodes { isResolved path line comments(first: 10) { nodes { body author { login } createdAt } } } } } } }' \
     -f owner=<owner> -f repo=<repo> -F number=<pr_number> \
     --jq '{
       pr_number: <pr_number>,
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
