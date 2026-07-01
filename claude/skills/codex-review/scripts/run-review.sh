#!/usr/bin/env bash
set -euo pipefail

# Run codex review for a given perspective against main.
# Usage: run-review.sh <perspective>
#   perspective: shell-senior | security | qa-fixture
#
# Output: codex exec's stdout (free-form text). The caller (SKILL.md) reads
# the verdict line to decide pass/fail and the next iteration.
#
# The review target is whatever git worktree the CALLER is in. This script
# deliberately does NOT `cd` — DOTFILES_ROOT is used only to locate the
# perspective prompt file, not to redirect git operations. All git commands
# below (and codex's own `git diff` inside `codex exec -`) run against $(pwd).
#
# Notes
# - Invoked via $HOME/.claude/skills/codex-review/scripts/run-review.sh, which is
#   a symlink target inside the dotfiles repo (claude/skills/ is symlinked).
# - `cd "$(dirname "$0")" && pwd -P` resolves to the dotfiles physical path so we
#   can locate codex/review-prompts/ without hardcoding $HOME or DOTFILES_DIR.

PERSPECTIVE="${1:-}"
if [ -z "$PERSPECTIVE" ]; then
  echo "ERROR: perspective required (shell-senior | security | qa-fixture)" >&2
  exit 1
fi

case "$PERSPECTIVE" in
  shell-senior|security|qa-fixture) ;;
  *)
    echo "ERROR: unknown perspective '$PERSPECTIVE' (expected: shell-senior | security | qa-fixture)" >&2
    exit 1
    ;;
esac

if ! command -v codex >/dev/null 2>&1; then
  echo "ERROR: codex CLI not installed" >&2
  exit 1
fi

# Resolve dotfiles root via the script's own location (works through the
# claude/skills symlink because `cd` + `pwd -P` resolves to the physical path).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# $SCRIPT_DIR == <dotfiles>/claude/skills/codex-review/scripts
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd -P)"

PROMPT_FILE="$DOTFILES_ROOT/codex/review-prompts/$PERSPECTIVE.md"
if [ ! -f "$PROMPT_FILE" ]; then
  echo "ERROR: prompt file not found: $PROMPT_FILE" >&2
  exit 1
fi

CWD="$(pwd -P)"

# Verify the caller's cwd is a git worktree before running any `git` command
# — otherwise the errors below would be misleading ("branch main not found"
# when the real issue is "not in a git repo at all"). Check the output rather
# than the exit code: `git rev-parse --is-inside-work-tree` prints `false`
# with exit 0 when cwd is inside a `.git/` internals directory, so a plain
# `if ! git rev-parse ...` guard would incorrectly let those cases through.
if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then
  echo "ERROR: not inside a git work tree (cwd: $CWD)" >&2
  exit 1
fi

BASE_BRANCH="main"
if ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
  echo "ERROR: base branch '$BASE_BRANCH' not found in current repo (cwd: $CWD)" >&2
  exit 1
fi

# Fail fast if the branch has no commits beyond main (matches SKILL.md
# pre-condition; saves an API call on empty diffs).
if [ "$(git rev-list --count "$BASE_BRANCH..HEAD")" -eq 0 ]; then
  echo "ERROR: no commits beyond $BASE_BRANCH on the current branch (cwd: $CWD)" >&2
  exit 1
fi

# codex review subcommand rejects --base + PROMPT in 0.142.3 (verified:
# `error: the argument '--base <BRANCH>' cannot be used with '[PROMPT]'`).
# Use codex exec instead and let the codex agent fetch the diff via its own
# shell tool. Base branch is referenced in the prompt body.
{
  cat "$PROMPT_FILE"
  printf '\n\n## Target\n\nReview the diff from `git diff %s...HEAD` of the current repository. Do NOT modify any files. Output only the verdict line and findings per the Output contract above.\n' "$BASE_BRANCH"
} | exec codex exec -
