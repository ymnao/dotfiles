#!/usr/bin/env bash
# eval fixture: contains deliberate redundancies that /simplify or the
# `code-reviewer` サブエージェント should flag. Used by dev/06 (review-loop-rerun) and
# dev/07 (review-loop-cap). Do not "fix" this file — evals depend on the
# redundancies.
# shellcheck disable=SC2034,SC2317

set -euo pipefail

# unused variable (redundancy #1)
unused_var="never referenced"

# duplicated helpers (redundancy #2, #3)
greet_a() {
    echo "hello $1"
}

greet_b() {
    echo "hello $1"
}

# dead branch (redundancy #4)
if false; then
    echo "unreachable"
fi

main() {
    greet_a "world"
    greet_b "world"
}

main "$@"
