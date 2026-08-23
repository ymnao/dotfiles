---
name: issue
description: Create a branch from a GitHub issue and propose an implementation plan
---

Fetch the specified issue, create a branch, and propose an implementation plan.

## Steps

1. Run `gh issue view <issue-number> --json number,title,body,labels,state,assignees,url --jq '{number, title, body, state, url, labels: [.labels[].name], assignees: [.assignees[].login]}'` to fetch issue info (the `--jq` projection normalizes `labels` and `assignees` to plain string arrays so the label-based branch-type rules below match by name)
    - Substitute `<issue-number>` with the number the user specified as the skill argument or in the conversation
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
7. Validate the generated name **before it is substituted into any command**. The issue title is attacker-controlled on a public repo, and git accepts shell metacharacters in ref names (`git check-ref-format --branch 'foo$(id);x'` exits 0), so a name carried straight into a command string gets expanded by the shell. Quoting is not the fix — `"$(...)"` still expands.
    - Write the generated name to `$TMPDIR/branch-name.txt` using your file-writing tool, **not** a shell redirect — the point is that the name must never appear in a command string (Claude Code: the Write tool; codex: `apply_patch`)
    - Run `LC_ALL=C awk 'NR>1 || $0 !~ /^[abcdefghijklmnopqrstuvwxyz0123456789][abcdefghijklmnopqrstuvwxyz0123456789\/._#-]*$/ {bad=1} END{exit (bad || NR!=1)}' "$TMPDIR/branch-name.txt"`
    - **exit 0** → the name is inside the safe set; substitute it literally in steps 8-9
    - **exit 1** → do NOT substitute it anywhere. Report the rejected name and stop
    - **Set a flag and decide in `END`; do not write `{exit 1}` in the main rule.** `exit` inside a main rule still runs `END`, and an `exit <expr>` there *replaces* the status — so `... {exit 1} END{exit NR!=1}` returns 0 for any single-line input, accepting `foo$(id);x`. Measured 2026-08-23: `printf 'x\n' | awk '{exit 7} END{exit 3}'` exits 3
    - The check requires the file to be **exactly one line** and that line to match. A per-line `grep -q` is not enough: it exits 0 as soon as *any* line matches, so a two-line name whose first line is safe and whose second is `$(id)` would pass and then have the newline act as a command separator. `git` itself rejects a newline in a ref name (`git check-ref-format --branch "$(printf 'a\nb')"` exits 128), but the name here is still a plain string with no ref behind it, so that protection has not applied yet
    - Do not swap the `awk` for `grep -qv`: the exit status of `-q` combined with `-v` is not consistent across grep implementations (measured with ugrep 7.8.4 — `grep -qvE` returns 1 on a file where `grep -vE` prints a non-matching line and returns 0)
    - The character class is spelled out instead of using ranges (`[a-z0-9]` collates differently per locale; same reason as `agents/hooks/block-dangerous-commands.sh`), and the first character is pinned to alphanumeric so a leading `-` cannot be read as an option by `git branch -d` / `git checkout`. `#` is in the set because the naming examples above use it, and a `#` that is not at the start of a word does not begin a shell comment
    - `tests/branch-name-validator/run-branch-name-validator-tests.sh` pins these exit codes and asserts that its own copy of the expression is byte-identical to the one above, so the two cannot drift apart
8. Check if the branch name already exists with `git rev-parse --verify <branch-name>`:
    - If it exists, report the conflict and stop
9. Run `git checkout -b <branch-name>` to create the branch
10. Explore the project structure:
    - Review directory layout
    - Understand existing code patterns and architecture
11. Propose an implementation plan based on the issue:
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
