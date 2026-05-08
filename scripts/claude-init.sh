#!/usr/bin/env bash
#
# claude-init.sh — Bootstrap Claude Code project config from dotfiles templates
#
# Usage:
#   claude-init.sh [--dir <path>] [--template <name>]
#
# Auto-detection:
#   package.json + pnpm-lock.yaml         → pnpm-node
#   package.json + package-lock.json      → npm-node
#   package.json + yarn.lock              → yarn-node
#   package.json + bun.lockb / bun.lock   → bun-node
#   uv.lock                               → python-uv
#   pyproject.toml + [tool.uv] section    → python-uv
#   （Poetry/Hatch/PDM 等は検出対象外。--template で明示するか、専用テンプレートの追加待ち）

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
  package.json + pnpm-lock.yaml         → pnpm-node
  package.json + package-lock.json      → npm-node
  package.json + yarn.lock              → yarn-node
  package.json + bun.lockb / bun.lock   → bun-node
  uv.lock                               → python-uv
  pyproject.toml + [tool.uv] section    → python-uv
  (Poetry/Hatch/PDM 等は検出対象外。--template で指定してください)
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
# Sets global TEMPLATE to the matched template name, or "" if no match.
# pyproject.toml だけでは Poetry/Hatch/PDM/setuptools と区別できないため、
# uv 固有のセクション ([tool.uv], [tool.uv.sources], [tool.uv.workspace] 等)
# がある場合のみ python-uv と確定する。
detect_template() {
    TEMPLATE=""
    if [[ -n "$TEMPLATE_OVERRIDE" ]]; then
        TEMPLATE="$TEMPLATE_OVERRIDE"
        return
    fi
    # Node 系テンプレは package.json + 各 package manager の lockfile で判別する。
    # 複数の lockfile が同居している場合は pnpm > npm > yarn > bun の順に優先。
    if [[ -f "$TARGET_DIR/package.json" ]]; then
        if [[ -f "$TARGET_DIR/pnpm-lock.yaml" ]]; then
            TEMPLATE="pnpm-node"
            return
        fi
        if [[ -f "$TARGET_DIR/package-lock.json" ]]; then
            TEMPLATE="npm-node"
            return
        fi
        if [[ -f "$TARGET_DIR/yarn.lock" ]]; then
            TEMPLATE="yarn-node"
            return
        fi
        # bun.lockb (binary, 旧) と bun.lock (text, Bun 1.2+) の両方をサポート。
        if [[ -f "$TARGET_DIR/bun.lockb" || -f "$TARGET_DIR/bun.lock" ]]; then
            TEMPLATE="bun-node"
            return
        fi
    fi
    if [[ -f "$TARGET_DIR/uv.lock" ]]; then
        TEMPLATE="python-uv"
        return
    fi
    if [[ -f "$TARGET_DIR/pyproject.toml" ]] \
        && grep -qE '^\[tool\.uv[].]' "$TARGET_DIR/pyproject.toml"; then
        TEMPLATE="python-uv"
        return
    fi
}

detect_template
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
# `git check-ignore` だと core.excludesfile / .git/info/exclude も拾うため、
# 実行者のグローバル ignore で既に無視されているとリポジトリ側 .gitignore に
# 追記されない。配布対象は repo の .gitignore なので、そのファイルを直接見る。
GITIGNORE="$TARGET_DIR/.gitignore"
IGNORE_ENTRY=".claude/settings.local.json"
if git -C "$TARGET_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    if [[ -f "$GITIGNORE" ]] && grep -Fxq "$IGNORE_ENTRY" "$GITIGNORE"; then
        skip ".gitignore: $IGNORE_ENTRY already present"
    else
        if [[ ! -f "$GITIGNORE" ]]; then
            touch "$GITIGNORE"
        fi
        {
            echo ""
            echo "# Claude Code"
            echo "$IGNORE_ENTRY"
        } >> "$GITIGNORE"
        info "Added $IGNORE_ENTRY to .gitignore"
    fi
else
    warn "Not a git repository — skipping .gitignore update"
fi

echo ""
info "Done. copied=$COPIED, skipped=$SKIPPED"
if [[ $SKIPPED -gt 0 ]]; then
    warn "Skipped files were not overwritten. Review with the diff commands shown above and merge manually if desired."
fi
