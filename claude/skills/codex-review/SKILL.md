---
name: codex-review
description: Run codex CLI as a second-opinion reviewer of the current diff vs the repo's default branch. Three perspectives (shell-senior / security / qa-fixture); findings are verified against the actual code before any fix is applied.
---

Use the `codex` CLI (independent LLM family) for a second-opinion review of the current branch's diff against the base branch (auto-detected from `origin/HEAD`, default `main`). For each perspective: detect → verify each finding against the real code → apply only confirmed findings that meet the threshold → re-run once to confirm.

## Pre-conditions

Check ALL of these before running. If any fails, report the stated message and stop:

1. The caller's current working directory must be inside the git worktree you want reviewed (or set `CODEX_REVIEW_REPO`).
2. `command -v codex` must succeed. If not → report "codex not installed".
3. `git rev-list --count <base>..HEAD` must be > 0 (base auto-detected; override via `CODEX_REVIEW_BASE`). If 0 → report "no commits beyond <base> to review". Uncommitted-only diffs are out of scope; commit first.

## Perspectives

| Name | Focus |
|------|-------|
| `shell-senior` | bash/POSIX, quoting, `set -euo pipefail` discipline, BSD↔GNU portability |
| `security` | secret leaks, command injection, permissions, input validation |
| `qa-fixture` | test coverage, fixtures, edge cases, determinism |

Default: run all 3 in the order above. If the user named one (`/codex-review security`), run only that.

## Steps (per perspective `<P>`)

### 1. Detect

Run `bash "$HOME/.claude/skills/codex-review/scripts/run-review.sh" <P>` and branch on the exit code:

- `0` (pass) → record perspective as PASS. Go to the next perspective.
- `2` (findings) → stdout is validated JSON. Parse `findings` and go to step 2.
- `1` (setup/parse error) → report the stderr message, record perspective as ERROR, and continue with the next perspective. If 2 consecutive perspectives end in ERROR, stop the whole skill and report to the user.

### 2. Verify (do this for EVERY finding BEFORE applying any fix)

For each finding, Read the actual `file`:`line` (and enough surrounding code to judge). Try to REFUTE the finding:

- The issue does not exist in the current code, is already handled elsewhere, or misreads the diff → verdict **REFUTED**. Record a one-line reason. Do not fix.
- The issue is real → verdict **CONFIRMED**.

### 3. Apply (use exactly these thresholds)

- CONFIRMED and (`severity` == "HIGH" or `confidence` >= 70) → fix in the working tree.
- CONFIRMED but below threshold → do NOT fix; record as REPORT-ONLY.
- REFUTED → do NOT fix.

Do not commit anything — leave fixes in the working tree for the user / `/pr`.

### 4. Confirm (only if fixes were applied)

Re-run step 1 for the SAME perspective exactly once. If it still returns findings, do NOT fix again — record the remaining findings as UNRESOLVED and move on. Max runs per perspective: 2 (one detect + one confirm).

## Report format

End with this table:

| Perspective | Verdict | Findings | Confirmed | Refuted | Fixed | Report-only | Unresolved |
|-------------|---------|----------|-----------|---------|-------|-------------|------------|
| shell-senior | PASS | 0 | - | - | - | - | - |
| security | FIXED | 3 | 2 | 1 | 2 | 0 | 0 |

Then per-perspective details, one line per finding:
`<severity>/<confidence> <file>:<line> — <issue> → <CONFIRMED+FIXED | CONFIRMED+REPORT-ONLY | REFUTED (reason) | UNRESOLVED>`

## Environment variables

| Variable | Effect |
|----------|--------|
| `CODEX_REVIEW_BASE` | Override the base branch. Default: `git symbolic-ref refs/remotes/origin/HEAD` → fallback `main`. |
| `CODEX_REVIEW_REPO` | `cd` into this directory before running git ops. Without it, the caller's cwd is the review target. |

## Notes

- **Review target = caller's cwd**: the script does not `cd` unless `CODEX_REVIEW_REPO` is set. This skill is not dotfiles-specific.
- **Output contract**: run-review.sh returns validated JSON (schema-checked by `parse-review-output.sh`). Exit codes: 0 pass / 2 findings / 1 error. Do NOT attempt to parse codex prose yourself; if you get exit 1, treat it as an error, not as PASS.
- **Why verify-then-fix**: cross-vendor reviewers have non-overlapping blind spots but also produce false positives; verification against the actual code filters them before they cost edit time. Detection is instructed to over-report ("report everything") and this skill filters downstream — do not skip verification because findings "look obviously right".
- **Do not commit** fixes from this skill.
- **Cost**: max 2 codex calls per perspective (detect + confirm), so max 6 calls for a full run. Confirm with the user before running on very large diffs.
- **Design: split file layout**: this skill's scripts live in `claude/skills/codex-review/scripts/`; the perspective prompts live in `codex/review-prompts/` (codex-facing content). The split is intentional — to tweak a perspective, edit the `.md` under `codex/review-prompts/`.
