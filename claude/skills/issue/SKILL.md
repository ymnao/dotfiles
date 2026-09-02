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
    - **exit 0** → the name is inside the safe set; steps 8-9 read it back out of the same file
    - **exit 1** → do NOT substitute it anywhere. Run `rm -f "$TMPDIR/branch-name.txt"` first, then report the rejected name and stop. Leaving a rejected name in the hand-off slot is what turns "the check stopped us" back into "the check only binds a cooperative agent": the file is at a fixed per-uid path, so a later run that resumes at step 8-9 reads the name that *failed* validation. Measured 2026-09-02: `git checkout -b "$(cat …)"` on a file holding `foo$(id);x` creates a branch by that literal name (no shell execution — the substitution output is not re-scanned — but the metacharacters land in a ref name, which is the thing step 7 exists to prevent)
    - Also run `LC_ALL=C tr -d '[:print:]\n' < "$TMPDIR/branch-name.txt" | LC_ALL=C wc -c` and require **0**. Whether the `awk` above sees past a NUL byte depends on the implementation: measured 2026-09-02, a 12-byte file holding `fix/a\0zzz;x\n` exits **0** under macOS awk (20200816), which ends the record at the NUL so `zzz;x` is never matched against the character class, and **1** under ubuntu's awk. `$(cat …)` hands the whole thing to git either way (bash drops the NUL), so on the implementations that pass it the validator reports "safe" about a prefix of what actually gets used — a vacuous pass, not a check. This gate does not depend on which awk you have
    - **Set a flag and decide in `END`; do not write `{exit 1}` in the main rule.** `exit` inside a main rule still runs `END`, and an `exit <expr>` there *replaces* the status — so `... {exit 1} END{exit NR!=1}` returns 0 for any single-line input, accepting `foo$(id);x`. Measured 2026-08-23: `printf 'x\n' | awk '{exit 7} END{exit 3}'` exits 3
    - The check requires the file to be **exactly one line** and that line to match. A per-line `grep -q` is not enough: it exits 0 as soon as *any* line matches, so a two-line name whose first line is safe and whose second is `$(id)` would pass and then have the newline act as a command separator. `git` itself rejects a newline in a ref name (`git check-ref-format --branch "$(printf 'a\nb')"` exits 128), but the name here is still a plain string with no ref behind it, so that protection has not applied yet
    - Do not swap the `awk` for `grep -qv`: the exit status of `-q` combined with `-v` is not consistent across grep implementations (measured with ugrep 7.8.4 — `grep -qvE` returns 1 on a file where `grep -vE` prints a non-matching line and returns 0)
    - The character class is spelled out instead of using ranges (`[a-z0-9]` collates differently per locale; same reason as `agents/hooks/block-dangerous-commands.sh`), and the first character is pinned to alphanumeric so a leading `-` cannot be read as an option by `git branch -d` / `git checkout`. `#` is in the set because the naming examples above use it, and a `#` that is not at the start of a word does not begin a shell comment
    - `tests/branch-name-validator/run-branch-name-validator-tests.sh` pins these exit codes and asserts that its own copy of the expression is byte-identical to the one above, so the two cannot drift apart
8. Check if the branch name already exists with `git rev-parse --verify "$(cat "$TMPDIR/branch-name.txt")"`:
    - No `--` before the name: `git rev-parse --verify -- main` exits 128 with `fatal: Needed a single revision` even when `main` exists, because `--` marks what follows as a *path*. Measured 2026-09-02 against a throwaway repo, with the no-`--` form on the same ref as the control (exit 0). With `--` this step can never detect a conflict, and the failure is silent — it looks exactly like "the branch does not exist"
    - If it exists, report the conflict and stop
9. Run `git checkout -b "$(cat "$TMPDIR/branch-name.txt")"` to create the branch
    - **Do not retype the name into these two commands.** Reading it back from the file that step 7 validated is what makes the check an actual gate: a name you type is a *different string* from the one that was checked, so the validation would only bind a cooperative agent. This is the same mechanical hand-off `/next` uses for `git branch -d` (the writer is a tool, the reader is the shell, and the name never passes through model output)
    - Run steps 7-9 in one pass. If you resume from step 8 or 9 without having written the file in this session, `$TMPDIR/branch-name.txt` is whatever a previous run left there — re-run step 7 rather than reading a stale name. `/next` guards its own hand-off file the same way (`next/SKILL.md` step 3), and deletes it afterwards; do the same here with `rm -f "$TMPDIR/branch-name.txt"` once the branch exists
    - There is no hook backing this up, and that is deliberate (issue #329). A `PreToolUse` hook that enforced the same character set on branch-name arguments was built and abandoned: to find *which* argument is the name it has to re-implement bash word splitting and git's `parse-options`, and every review round found a new form that slipped through — `2>&1` and IO numbers, a `}` inside the name (`git checkout -b 'x}'` + a substitution), process substitution, a value starting with `-`, the whole command wrapped in `$(...)`, and finally this repo's own `git/config` aliases (`co` = `checkout`, `br` = `branch`), which are user-defined and so cannot be enumerated at all. It also rejected valid ref names (`feature/日本語`, `feature/x@2`, `"${branches[@]}"`) in every repo it applied to. The hand-off above removes the retyping step itself, which is the thing the hook was approximating
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
