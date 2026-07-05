---
name: issue
description: Create a branch from a GitHub issue and propose an implementation plan
---

Fetch the specified issue, create a branch, and propose an implementation plan.

## Steps

1. Run `gh issue view <issue-number> --json number,title,body,labels,state,assignees,url --jq '{number, title, body, state, url, labels: [.labels[].name], assignees: [.assignees[].login]}'` to fetch issue info, substituting `<issue-number>` with the number the user specified — as the skill argument or in the conversation (the `--jq` projection normalizes `labels` and `assignees` to plain string arrays so the label-based branch-type rules below match by name)
    - If no issue number was provided, ask the user for it and stop
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
    - Derive an appropriate name from the issue title (e.g., `feature/add-user-auth-#42`, `fix/login-redirect-loop-#15`)
7. Check if the branch name already exists with `git rev-parse --verify <branch-name>`:
    - If it exists, report the conflict and stop
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
