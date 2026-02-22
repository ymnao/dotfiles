---
name: resolve
description: Fetch and address unresolved PR review comments
disable-model-invocation: true
---

Fetch unresolved review threads for the current PR and address each one.

## Steps

1. Run `bash "$HOME/.claude/skills/resolve/scripts/fetch-unresolved-reviews.sh"` to get unresolved review threads
2. If `unresolved_threads` is empty, report that there are no unresolved comments and stop
3. For each thread:
   - Read the relevant file and line to understand the current state
   - Evaluate whether the suggestion is valid
   - If valid, fix the code (apply best practices regardless of effort)
   - If unnecessary or inappropriate, prepare a clear reason
4. If any fixes were made, run all applicable verification steps for the project:
   - Lint / static analysis
   - Format check
   - Type check
   - Build
   - Unit tests
   - Integration tests
   - E2E tests
   - Determine available commands from package.json, Makefile, pyproject.toml, Cargo.toml, etc.
5. Commit and push
6. Report all results in the format below

## Report format

| # | Comment | Action | Reason |
|---|---------|--------|--------|
| 1 | ... | Fixed (commit hash) | ... |
| 2 | ... | Won't fix | ... |
