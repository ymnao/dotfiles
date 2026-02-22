---
name: issue
description: Create a branch from a GitHub issue and propose an implementation plan
args: <issue number>
---

Fetch the specified issue, create a branch, and propose an implementation plan.

## Steps

1. Run `bash "$HOME/.claude/skills/issue/scripts/fetch-issue.sh" $ARGUMENTS` to fetch issue info
2. Check issue state:
   - If `CLOSED`, report that the issue is already closed and stop
3. Check for uncommitted changes:
   - If `git status --porcelain` shows uncommitted changes, report and stop
4. If not on the repository's default branch, check out the default branch first
5. Determine branch type:
   - Label contains `bug` → `fix/`
   - Label contains `documentation` → `docs/`
   - Label contains `refactor` → `refactor/`
   - Otherwise → `feature/`
   - Also consider the issue title and body content
6. Generate branch name:
   - Format: `<type>/<concise-english-description>`
   - Use lowercase and hyphens
   - Derive an appropriate name from the issue title (e.g., `feature/add-user-auth`, `fix/login-redirect-loop`)
7. Check if the branch name already exists with `git rev-parse --verify <branch-name>`:
   - If it exists, report the conflict and let the user decide
8. Run `git checkout -b <branch-name>` to create the branch
9. Explore the project structure:
   - Review directory layout
   - Understand existing code patterns and architecture
10. Propose an implementation plan based on the issue:
   - Files to change
   - Implementation steps
   - Considerations and caveats

## Report format

### Issue #<number>: <title>

**Branch**: `<created branch name>`

**Implementation plan**:

1. ...
2. ...
3. ...

**Notes**:
- ...
