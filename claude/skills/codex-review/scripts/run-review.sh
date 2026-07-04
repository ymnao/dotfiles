#!/usr/bin/env bash
set -euo pipefail

# Run codex review for a given perspective against the repo's default branch.
# Usage: run-review.sh <perspective>
#   perspective: shell-senior | security | qa-fixture
#
# Optional environment variables:
#   CODEX_REVIEW_BASE  Override the base branch (default: auto-detected from
#                      refs/remotes/origin/HEAD, falls back to "main").
#   CODEX_REVIEW_REPO  cd into this directory before running git ops. Without
#                      it, the caller's cwd is the review target.
#
# Output: validated review JSON on stdout (single line, schema-checked by
# parse-review-output.sh).
# Exit codes: 0 = verdict pass / 2 = findings / 1 = setup or parse error.
#
# The review target is the caller's cwd (or CODEX_REVIEW_REPO if set). This
# script does not `cd` unless CODEX_REVIEW_REPO is set. DOTFILES_ROOT is used
# only to locate the perspective prompt file, not to redirect git operations.
#
# Notes
# - Invoked via $HOME/.claude/skills/codex-review/scripts/run-review.sh, which
#   is a symlink target inside the dotfiles repo (claude/skills/ is symlinked).
# - `cd "$(dirname "$0")" && pwd -P` resolves to the dotfiles physical path so
#   we can locate codex/review-prompts/ and scripts/lib/log.sh without
#   hardcoding $HOME or DOTFILES_DIR.

PERSPECTIVE="${1:-}"

# Resolve dotfiles root first so we can source shared log helpers.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# $SCRIPT_DIR == <dotfiles>/claude/skills/codex-review/scripts
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd -P)"

# shellcheck source=../../../../scripts/lib/log.sh
source "$DOTFILES_ROOT/scripts/lib/log.sh"

if [ -z "$PERSPECTIVE" ]; then
  error "perspective required (shell-senior | security | qa-fixture)"
fi

case "$PERSPECTIVE" in
  shell-senior|security|qa-fixture) ;;
  *)
    error "unknown perspective '$PERSPECTIVE' (expected: shell-senior | security | qa-fixture)"
    ;;
esac

if ! command -v codex >/dev/null 2>&1; then
  error "codex CLI not installed"
fi

PROMPT_FILE="$DOTFILES_ROOT/codex/review-prompts/$PERSPECTIVE.md"
if [ ! -f "$PROMPT_FILE" ]; then
  error "prompt file not found: $PROMPT_FILE"
fi

PARSER="$SCRIPT_DIR/parse-review-output.sh"
if [ ! -f "$PARSER" ]; then
  error "parser not found: $PARSER"
fi

# Switch to CODEX_REVIEW_REPO if set — this is the escape hatch when the
# caller cannot cd (e.g. an agent shell whose cwd is fixed). Without it, the
# caller's own cwd is the review target.
if [ -n "${CODEX_REVIEW_REPO:-}" ]; then
  if ! cd "$CODEX_REVIEW_REPO" 2>/dev/null; then
    error "cannot cd to CODEX_REVIEW_REPO='$CODEX_REVIEW_REPO'"
  fi
fi

# `pwd -P` can fail if the directory was removed between shell startup and
# now — fall back to a sentinel so error messages remain useful instead of
# dying silently under set -e.
CWD="$(pwd -P 2>/dev/null || echo '(unknown)')"

# Verify cwd is a git worktree before running any `git` command — otherwise
# the errors below would be misleading. Check the OUTPUT rather than the
# exit code: `git rev-parse --is-inside-work-tree` prints `false` with exit 0
# when cwd is inside a `.git/` internals directory, so a plain
# `if ! git rev-parse ...` guard would let those cases through.
if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then
  error "not inside a git work tree (cwd: $CWD)"
fi

# Detect the default branch: prefer $CODEX_REVIEW_BASE, then origin/HEAD, then
# fall back to "main". This lets the skill work on repos whose default is
# `master` / `develop` / `trunk` without hardcoding.
if [ -n "${CODEX_REVIEW_BASE:-}" ]; then
  BASE_BRANCH="$CODEX_REVIEW_BASE"
elif BASE_BRANCH="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)"; then
  BASE_BRANCH="${BASE_BRANCH#refs/remotes/origin/}"
else
  BASE_BRANCH="main"
fi

if ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
  error "base branch '$BASE_BRANCH' not found in current repo (cwd: $CWD). Set CODEX_REVIEW_BASE to override."
fi

# Fail fast if the branch has no commits beyond base (matches SKILL.md
# pre-condition; saves an API call on empty diffs).
if [ "$(git rev-list --count "$BASE_BRANCH..HEAD")" -eq 0 ]; then
  error "no commits beyond $BASE_BRANCH on the current branch (cwd: $CWD)"
fi

# Fetch the diff once and embed it in the prompt so codex does not need to
# spawn its own `git diff` on every iteration. Trade-off: larger prompt payload
# on huge diffs. For typical PR-sized reviews this is a wash for tokens but
# avoids codex agent's own cwd ambiguity — codex sees the diff as given.
DIFF_CONTENT="$(git diff "$BASE_BRANCH...HEAD")"

# codex review subcommand rejects --base + PROMPT in 0.142.3 (verified:
# `error: the argument '--base <BRANCH>' cannot be used with '[PROMPT]'`).
# Use codex exec instead with the diff embedded. Command names in the prompt
# body are wrapped in double quotes rather than backticks to avoid any risk
# of shell command-substitution interpretation on codex's side.
#
# codex の生出力は一時ファイルに保存し、parse-review-output.sh で
# JSON 抽出+schema 検証してから返す。exit code はパーサのものを継承する
# (0 = pass / 2 = findings / 1 = parse error)。
RAW_OUT="$(mktemp "${TMPDIR:-/tmp}/codex-review.XXXXXX")"
cleanup() { [ -n "${RAW_OUT:-}" ] && rm -f "$RAW_OUT"; }
trap cleanup EXIT

{
  cat "$PROMPT_FILE"
  printf '\n\n## Target\n\nReview the diff below (produced by "git diff %s...HEAD" in %s). Do NOT modify any files. Output only the fenced JSON block per the Output contract above.\n\n```diff\n%s\n```\n' \
    "$BASE_BRANCH" "$CWD" "$DIFF_CONTENT"
# --sandbox read-only を明示。config.toml のデフォルト (workspace-write 等)
# に依存すると、レビュー中に codex が working tree を書き換える構成になる
# 環境が生まれうる。プロンプトの「Do NOT modify」は副次的な多層防御で、
# 主防御はここで CLI に強制する。不明フラグなら codex が非ゼロ exit し
# パーサが exit 1 (setup error) として顕在化するので、サイレントに権限が
# 緩むパスはない。
} | codex exec --sandbox read-only - > "$RAW_OUT"

rc=0
bash "$PARSER" < "$RAW_OUT" || rc=$?
exit "$rc"
