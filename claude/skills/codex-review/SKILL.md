---
name: codex-review
description: Run codex CLI as a second-opinion reviewer of the current diff vs the repo's default branch. Three perspectives (shell-senior / security / qa-fixture), iterated per perspective until codex reports "OK".
---

Use the `codex` CLI (independent LLM family) for a second-opinion review of the current branch's diff against the base branch (auto-detected from `origin/HEAD`, default `main`). Three perspectives run sequentially. For each perspective, loop fix→re-review until codex says "OK" or you hit the iteration cap.

## Pre-conditions

Before running:

1. The caller's current working directory must be inside the git worktree you want reviewed. (See Notes: "Review target = caller's cwd" for the mechanism, or set `CODEX_REVIEW_REPO` to override.)
2. `command -v codex` must succeed. If not, report "codex not installed" and stop.
3. `git rev-list --count <base>..HEAD` must be > 0 (base branch auto-detected; overridable via `CODEX_REVIEW_BASE`). If 0, report "no commits beyond <base> to review" and stop. (Uncommitted-only diffs are out of scope; commit first.)

## Perspectives

| Name | Focus |
|------|-------|
| `shell-senior` | bash/POSIX, quoting, `set -euo pipefail` discipline, BSD↔GNU portability |
| `security` | secret leaks, command injection, permissions, input validation |
| `qa-fixture` | test coverage, fixtures, edge cases, determinism |

## Steps

Default: run all 3 perspectives in the order above. If the user named one (`/codex-review security`), run only that.

For each perspective `<P>`:

1. Run `bash "$HOME/.claude/skills/codex-review/scripts/run-review.sh" <P>`. This pipes the perspective prompt (with the pre-fetched `git diff <base>...HEAD` embedded) into `codex exec -` and streams codex's verdict to stdout.
2. Read the output:
   - **Verdict line** is `OK: no <perspective> concerns` (single line, no other findings; e.g. `OK: no shell-senior concerns`) → perspective passed, move to the next perspective.
   - Otherwise → codex listed findings. For each:
     - Genuine issue → apply the fix in the working tree (no commit yet — `/pr` or a manual commit comes later).
     - False positive → record your reasoning; do not fix.
3. After applying fixes, re-run step 1 for the **same** perspective.
4. Cap: **3 iterations per perspective**. If codex is still not "OK" at iteration 3, record the remaining findings as `UNRESOLVED` and proceed to the next perspective. Do not loop forever.

## Environment variables

| Variable | Effect |
|----------|--------|
| `CODEX_REVIEW_BASE` | Override the base branch. Default: `git symbolic-ref refs/remotes/origin/HEAD` → fallback `main`. Useful when reviewing against `master` / `develop` / a feature-integration branch. |
| `CODEX_REVIEW_REPO` | `cd` into this directory before running git ops. Use when the caller's cwd cannot be changed. Without it, the caller's cwd is the review target. |

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

- **Review target = caller's cwd**: The script does not `cd` unless `CODEX_REVIEW_REPO` is set. All git operations (the pre-flight guards and the pre-fetched diff) run against `$(pwd)`. This skill is not dotfiles-specific; it reviews whichever repo you're in.
- **codex-side cwd caveat**: codex CLI may honor `[projects.*]` entries in `~/.codex/config.toml`. The script mitigates this by pre-fetching `git diff <base>...HEAD` and embedding it in the prompt, so codex does not need to run its own `git diff` and its internal cwd handling does not affect the review target.
- **Do not commit** fixes from this skill. Leave them in the working tree so the user can review and `/pr` separately.
- **Cost**: `codex exec` invokes the OpenAI API (gpt-5.5 per `~/.codex/config.toml`). 3 perspectives × up to 3 iterations = up to 9 API calls. Confirm with the user before running on large diffs. For very large diffs the embedded-diff payload may be significant — consider filtering with `CODEX_REVIEW_BASE` to a narrower base.
- **Output contract**: each prompt instructs codex to terminate with a single `OK: ...` line on pass, or a bulleted findings list on fail. Use those as the loop signal. If codex deviates (e.g. mixes prose), make a best-effort read — treat "OK"-leaning text with no enumerated issues as PASS.
- **Design: split file layout**: the script lives in `claude/skills/codex-review/` (Claude-side skill entry point) and the perspective prompts live in `codex/review-prompts/` (codex-facing content, so a future codex-side skill could reuse the same prompts). Do not consolidate the two — the split is intentional. To tweak a perspective, edit the corresponding `.md` under `codex/review-prompts/`.

## Future improvements

- **Exit-code semantics**: `run-review.sh` currently prints codex's raw stdout and inherits codex's exit code. A future refactor could parse the verdict line and return `0 = OK` / `2 = findings` / `1 = setup error`, letting a CI or agent chain the skill without regex-parsing text.
- **Diff embedding trade-off**: the script pre-fetches the diff and embeds it in the prompt (avoids codex's own cwd ambiguity and per-iteration re-reads). For very large diffs this bloats the prompt payload; a size-thresholded fallback (embed if <100KB, otherwise instruct codex to fetch) would rebalance the trade-off.
