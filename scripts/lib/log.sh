# shellcheck shell=bash
#
# log.sh — Shared color/log helpers for dotfiles scripts.
# Source-only. `error` writes to stderr and terminates the caller (exit 1).
#
# Usage:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=lib/log.sh
#   source "$SCRIPT_DIR/lib/log.sh"
#   info "..."; warn "..."; skip "..."; error "..."

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

info()  { printf '%s[INFO]%s %s\n'  "$GREEN"  "$NC" "$1"; }
warn()  { printf '%s[WARN]%s %s\n'  "$YELLOW" "$NC" "$1"; }
skip()  { printf '%s[SKIP]%s %s\n'  "$BLUE"   "$NC" "$1"; }
error() { printf '%s[ERROR]%s %s\n' "$RED"    "$NC" "$1" >&2; exit 1; }
