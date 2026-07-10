#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck source-path=SCRIPTDIR source=lib/backup.sh
source "$SCRIPT_DIR/lib/backup.sh"

# Check for Windows
case "$(uname -s)" in
    CYGWIN*|MINGW*|MSYS*|Windows_NT)
        error "Windows detected. Please use PowerShell script instead:
    .\\scripts\\link.ps1

For detailed Windows setup instructions, see README.md"
        ;;
esac

# Dotfiles directory
DOTFILES_DIR="${SCRIPT_DIR%/*}"

# Ensure ~/.config exists
mkdir -p "$HOME/.config"

# Link function
link_file() {
    local src="$1"
    local dest="$2"

    # If destination exists and is not a symlink, back it up
    if [[ -e "$dest" ]] && [[ ! -L "$dest" ]]; then
        local backup
        backup=$(unique_backup_path "$dest")
        warn "Backing up existing file: $dest -> $backup"
        mv "$dest" "$backup"
    fi

    # Remove old symlink if it exists
    if [[ -L "$dest" ]]; then
        rm "$dest"
    fi

    # Create parent directory if needed
    mkdir -p "$(dirname "$dest")"

    # Create symlink
    ln -sf "$src" "$dest"
    info "Linked: $dest -> $src"
}

# Link WezTerm configuration
if [[ -d "$DOTFILES_DIR/wezterm" ]]; then
    link_file "$DOTFILES_DIR/wezterm" "$HOME/.config/wezterm"
fi

# Link Neovim configuration
if [[ -d "$DOTFILES_DIR/nvim" ]]; then
    link_file "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
fi

# Link Karabiner configuration
if [[ -d "$DOTFILES_DIR/karabiner" ]]; then
    link_file "$DOTFILES_DIR/karabiner" "$HOME/.config/karabiner"
fi

# Link Fish configuration
if [[ -d "$DOTFILES_DIR/fish" ]]; then
    link_file "$DOTFILES_DIR/fish" "$HOME/.config/fish"
fi

# Git configuration
mkdir -p "$HOME/.config/git"

if [[ -f "$DOTFILES_DIR/git/config" ]]; then
    link_file "$DOTFILES_DIR/git/config" "$HOME/.config/git/config"
fi

if [[ -f "$DOTFILES_DIR/git/ignore" ]]; then
    link_file "$DOTFILES_DIR/git/ignore" "$HOME/.config/git/ignore"
fi

# Link GitHub CLI configuration
if [[ -f "$DOTFILES_DIR/gh/config.yml" ]]; then
    mkdir -p "$HOME/.config/gh"
    link_file "$DOTFILES_DIR/gh/config.yml" "$HOME/.config/gh/config.yml"
fi

# Link npm/pnpm configuration
if [[ -f "$DOTFILES_DIR/npm/npmrc" ]]; then
    link_file "$DOTFILES_DIR/npm/npmrc" "$HOME/.npmrc"
fi

# Ensure Claude configuration directory exists if needed
if [[ -f "$DOTFILES_DIR/agents/AGENTS.md" ]] || [[ -d "$DOTFILES_DIR/claude" ]]; then
    mkdir -p "$HOME/.claude"
fi

# AI Agent guidelines (AGENTS.md → ~/.claude/CLAUDE.md)
if [[ -f "$DOTFILES_DIR/agents/AGENTS.md" ]]; then
    link_file "$DOTFILES_DIR/agents/AGENTS.md" "$HOME/.claude/CLAUDE.md"
fi

# Claude Code configuration
if [[ -d "$DOTFILES_DIR/claude" ]]; then
    if [[ -f "$DOTFILES_DIR/claude/settings.json" ]]; then
        link_file "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json"
    fi

    if [[ -d "$DOTFILES_DIR/claude/skills" ]]; then
        link_file "$DOTFILES_DIR/claude/skills" "$HOME/.claude/skills"
    fi

    if [[ -d "$DOTFILES_DIR/claude/hooks" ]]; then
        link_file "$DOTFILES_DIR/claude/hooks" "$HOME/.claude/hooks"
    fi

    if [[ -d "$DOTFILES_DIR/claude/agents" ]]; then
        link_file "$DOTFILES_DIR/claude/agents" "$HOME/.claude/agents"
    fi

    if [[ -d "$DOTFILES_DIR/claude/rules" ]]; then
        link_file "$DOTFILES_DIR/claude/rules" "$HOME/.claude/rules"
    fi

    if [[ -f "$DOTFILES_DIR/claude/statusline.sh" ]]; then
        link_file "$DOTFILES_DIR/claude/statusline.sh" "$HOME/.claude/statusline.sh"
    fi
fi

# Codex CLI configuration
if [[ -d "$DOTFILES_DIR/codex" ]]; then
    mkdir -p "$HOME/.codex"

    if [[ -f "$DOTFILES_DIR/codex/AGENTS.md" ]]; then
        link_file "$DOTFILES_DIR/codex/AGENTS.md" "$HOME/.codex/AGENTS.md"
    fi

    # config.toml は symlink ではなくマージ方式
    # Codex CLI は [projects.*] / [plugins.*] / [hooks.state] 等を ~/.codex/config.toml に
    # 動的に書き込むため、symlink にすると dotfiles リポジトリが汚染される。
    # マージスクリプトで base を上書きしつつ Codex 管理セクションを保持する。
    if [[ -f "$DOTFILES_DIR/codex/config.toml" ]]; then
        bash "$SCRIPT_DIR/codex-merge-config.sh" \
            "$DOTFILES_DIR/codex/config.toml" \
            "$HOME/.codex/config.toml"
    fi

    if [[ -f "$DOTFILES_DIR/codex/hooks.json" ]]; then
        link_file "$DOTFILES_DIR/codex/hooks.json" "$HOME/.codex/hooks.json"
    fi

    if [[ -d "$DOTFILES_DIR/codex/hooks" ]]; then
        link_file "$DOTFILES_DIR/codex/hooks" "$HOME/.codex/hooks"
    fi

    # skills は per-skill 個別 symlink にする（Codex CLI が管理する .system/ と共存させるため）
    if [[ -d "$DOTFILES_DIR/codex/skills" ]]; then
        # 既存の skills ディレクトリ自体が symlink（旧 link.sh の挙動）なら削除して実体ディレクトリに置き換える
        if [[ -L "$HOME/.codex/skills" ]]; then
            rm "$HOME/.codex/skills"
        fi
        mkdir -p "$HOME/.codex/skills"
        for skill_path in "$DOTFILES_DIR/codex/skills"/*/; do
            [[ -d "$skill_path" ]] || continue
            skill_name=$(basename "$skill_path")
            link_file "${skill_path%/}" "$HOME/.codex/skills/$skill_name"
        done
    fi
fi

info "All symlinks created successfully!"
