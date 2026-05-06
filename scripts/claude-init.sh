#!/usr/bin/env bash
#
# claude-init.sh — Bootstrap Claude Code project config from dotfiles templates
#
# Usage:
#   claude-init.sh [--dir <path>] [--template <name>]
#
# Auto-detection:
#   package.json → ts-node

set -euo pipefail

# --- Constants ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$DOTFILES_DIR/claude/templates"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
skip()  { echo -e "${BLUE}[SKIP]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

# --- Args ---
TARGET_DIR="$PWD"
TEMPLATE_OVERRIDE=""

usage() {
    cat <<EOF
Usage: $0 [--dir <path>] [--template <name>]

Options:
  --dir <path>       Target project directory (default: current directory)
  --template <name>  Force specific template (skip auto-detection)
  -h, --help         Show this help

Available templates:
$(ls -1 "$TEMPLATES_DIR" 2>/dev/null | sed 's/^/  - /')

Auto-detection rules:
  package.json → ts-node
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)      TARGET_DIR="$2"; shift 2 ;;
        --template) TEMPLATE_OVERRIDE="$2"; shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        *)          error "Unknown argument: $1" ;;
    esac
done

# --- Validate ---
if [[ ! -d "$TARGET_DIR" ]]; then
    error "Target directory not found: $TARGET_DIR"
fi
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

if [[ "$TARGET_DIR" == "$DOTFILES_DIR" ]]; then
    error "Cannot run on the dotfiles repository itself (it has its own .claude/settings.json)"
fi

# --- Detect template ---
detect_template() {
    if [[ -n "$TEMPLATE_OVERRIDE" ]]; then
        echo "$TEMPLATE_OVERRIDE"
        return
    fi
    if [[ -f "$TARGET_DIR/package.json" ]]; then
        echo "ts-node"
        return
    fi
    echo ""
}

TEMPLATE="$(detect_template)"
if [[ -z "$TEMPLATE" ]]; then
    error "Cannot detect project type. Specify with --template <name>. Run with --help to see available templates."
fi

TEMPLATE_DIR="$TEMPLATES_DIR/$TEMPLATE"
if [[ ! -d "$TEMPLATE_DIR" ]]; then
    error "Template not found: $TEMPLATE_DIR"
fi

info "Target:   $TARGET_DIR"
info "Template: $TEMPLATE"
echo ""

# --- Apply template files (no overwrite) ---
COPIED=0
SKIPPED=0
while IFS= read -r -d '' src; do
    rel="${src#"$TEMPLATE_DIR/"}"
    dst="$TARGET_DIR/$rel"

    if [[ -e "$dst" ]]; then
        skip "Exists: $rel"
        echo "       Compare: diff -u \"$dst\" \"$src\""
        SKIPPED=$((SKIPPED + 1))
    else
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        info "Created: $rel"
        COPIED=$((COPIED + 1))
    fi
done < <(find "$TEMPLATE_DIR" -type f -print0)

echo ""

# --- Update .gitignore ---
GITIGNORE="$TARGET_DIR/.gitignore"
if git -C "$TARGET_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    if git -C "$TARGET_DIR" check-ignore -q .claude/settings.local.json 2>/dev/null; then
        skip ".gitignore: .claude/settings.local.json already ignored"
    else
        if [[ ! -f "$GITIGNORE" ]]; then
            touch "$GITIGNORE"
        fi
        {
            echo ""
            echo "# Claude Code"
            echo ".claude/settings.local.json"
        } >> "$GITIGNORE"
        info "Added .claude/settings.local.json to .gitignore"
    fi
else
    warn "Not a git repository — skipping .gitignore update"
fi

echo ""
info "Done. copied=$COPIED, skipped=$SKIPPED"
if [[ $SKIPPED -gt 0 ]]; then
    warn "Skipped files were not overwritten. Review with the diff commands shown above and merge manually if desired."
fi
