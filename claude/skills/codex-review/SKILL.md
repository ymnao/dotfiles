---
name: codex-review
description: Run codex CLI as a second-opinion reviewer of the current diff vs main. Three perspectives (shell-senior / security / qa-fixture), iterated per perspective until codex reports "OK".
---

Use the `codex` CLI (independent LLM family) for a second-opinion review of the current branch's diff against `main`. Three perspectives run sequentially. For each perspective, loop fix→re-review until codex says "OK" or you hit the iteration cap.

## Pre-conditions

Before running:

1. The caller's current working directory must be inside the git worktree you want reviewed — the script does not `cd`, and all git operations (the pre-flight guards and codex's own `git diff` inside `codex exec -`) run against `$(pwd)`. This skill is not dotfiles-specific; it reviews whichever repo you're in.
2. `command -v codex` must succeed. If not, report "codex not installed" and stop.
3. `git rev-list --count main..HEAD` must be > 0. If 0, report "no commits beyond main to review" and stop. (Uncommitted-only diffs are out of scope; commit first.)

## Perspectives

| Name | Focus |
|------|-------|
| `shell-senior` | bash/POSIX, quoting, `set -euo pipefail` discipline, BSD↔GNU portability |
| `security` | secret leaks, command injection, permissions, input validation |
| `qa-fixture` | test coverage, fixtures, edge cases, determinism |

## Steps

Default: run all 3 perspectives in the order above. If the user named one (`/codex-review security`), run only that.

For each perspective `<P>`:

1. Run `bash "$HOME/.claude/skills/codex-review/scripts/run-review.sh" <P>`. This pipes the perspective prompt (with a "review `git diff main...HEAD`" directive appended) into `codex exec -` and streams codex's verdict to stdout.
2. Read the output:
   - **Verdict line** is `OK: no <perspective> concerns` (single line, no other findings; e.g. `OK: no shell-senior concerns`) → perspective passed, move to the next perspective.
   - Otherwise → codex listed findings. For each:
     - Genuine issue → apply the fix in the working tree (no commit yet — `/pr` or a manual commit comes later).
     - False positive → record your reasoning; do not fix.
3. After applying fixes, re-run step 1 for the **same** perspective.
4. Cap: **3 iterations per perspective**. If codex is still not "OK" at iteration 3, record the remaining findings as `UNRESOLVED` and proceed to the next perspective. Do not loop forever.

## Report format

At the end, report a table:

| Perspective | Iterations | Verdict | Fixes applied | Remaining findings |
|-------------|------------|---------|---------------|--------------------|
| shell-senior | 2 | PASS | 3 | 0 |
| security | 3 | UNRESOLVED | 1 | 2 |
| qa-fixture | 1 | PASS | 0 | 0 |

Followed by per-perspective notes:

- What was fixed (file:line + one-line summary).
- What was deemed false positive (with reasoning).

If any perspective is `UNRESOLVED`, list the remaining findings for the user to triage.

## Notes

- **Do not commit** fixes from this skill. Leave them in the working tree so the user can review and `/pr` separately.
- **Cost**: `codex exec` invokes the OpenAI API (gpt-5.5 per `~/.codex/config.toml`). 3 perspectives × up to 3 iterations = up to 9 API calls. Confirm with the user before running on large diffs.
- **Output contract**: each prompt instructs codex to terminate with a single `OK: ...` line on pass, or a bulleted findings list on fail. Use those as the loop signal. If codex deviates (e.g. mixes prose), make a best-effort read — treat "OK"-leaning text with no enumerated issues as PASS.
- The script and prompts live in `claude/skills/codex-review/` and `codex/review-prompts/` respectively. To tweak a perspective, edit the corresponding `.md` under `codex/review-prompts/`.
