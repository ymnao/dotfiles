#!/usr/bin/env bash
#
# claude-init.sh — Bootstrap Claude Code project config from dotfiles templates
#
# Usage:
#   claude-init.sh [--dir <path>] [--template <name>]
#
# Auto-detection:
#   package.json + pnpm-lock.yaml → ts-node
#   uv.lock                       → python-uv
#   pyproject.toml (only)         → python-uv (warning: uv.lock 未検出)
#   （npm/yarn/bun のリポは検出対象外。--template で明示するか、
#    専用テンプレートの追加待ち）

set -euo pipefail

# --- Constants ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${SCRIPT_DIR%/*}"
TEMPLATES_DIR="$DOTFILES_DIR/claude/templates"

# shellcheck source-path=SCRIPTDIR source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"

# --- Args ---
TARGET_DIR="$PWD"
TEMPLATE_OVERRIDE=""

usage() {
    local templates_list="  (no templates found)"
    if [[ -d "$TEMPLATES_DIR" ]]; then
        local listing
        listing=$(ls -1 "$TEMPLATES_DIR" 2>/dev/null | sed 's/^/  - /' || true)
        [[ -n "$listing" ]] && templates_list="$listing"
    fi
    cat <<EOF
Usage: $0 [--dir <path>] [--template <name>]

Options:
  --dir <path>       Target project directory (default: current directory)
  --template <name>  Force specific template (skip auto-detection)
  -h, --help         Show this help

Available templates:
$templates_list

Auto-detection rules:
  package.json + pnpm-lock.yaml → ts-node
  uv.lock                       → python-uv
  pyproject.toml (only)         → python-uv (warning)
  (npm/yarn/bun リポは現状検出対象外。--template で指定してください)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)
            [[ $# -ge 2 ]] || error "--dir requires a value"
            TARGET_DIR="$2"; shift 2 ;;
        --template)
            [[ $# -ge 2 ]] || error "--template requires a value"
            TEMPLATE_OVERRIDE="$2"; shift 2 ;;
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
# Sets globals: TEMPLATE (template name or "") and TEMPLATE_FUZZY
# (1 = match was a heuristic guess that warrants a warning).
detect_template() {
    TEMPLATE=""
    TEMPLATE_FUZZY=0
    if [[ -n "$TEMPLATE_OVERRIDE" ]]; then
        TEMPLATE="$TEMPLATE_OVERRIDE"
        return
    fi
    # ts-node テンプレートは pnpm 専用なので、pnpm-lock.yaml がある場合のみ採用。
    # 他の package manager (npm/yarn/bun) は誤分類になるため検出しない。
    if [[ -f "$TARGET_DIR/package.json" && -f "$TARGET_DIR/pnpm-lock.yaml" ]]; then
        TEMPLATE="ts-node"
        return
    fi
    if [[ -f "$TARGET_DIR/uv.lock" ]]; then
        TEMPLATE="python-uv"
        return
    fi
    # uv.lock が無くても pyproject.toml だけで python-uv と推定するが、
    # Poetry/Hatch/PDM の可能性もあるので fuzzy フラグを立てる
    if [[ -f "$TARGET_DIR/pyproject.toml" ]]; then
        TEMPLATE="python-uv"
        TEMPLATE_FUZZY=1
        return
    fi
}

detect_template
if [[ -z "$TEMPLATE" ]]; then
    error "Cannot detect project type. Specify with --template <name>. Run with --help to see available templates."
fi

if (( TEMPLATE_FUZZY )); then
    warn "uv.lock not found — assuming python-uv. If this project uses Poetry/Hatch/PDM/etc, override with --template <name>."
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
