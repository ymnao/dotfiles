#!/usr/bin/env bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

skip() {
    echo -e "${BLUE}[SKIP]${NC} $1"
}

# Dotfiles directory
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Ensure ~/.config exists
mkdir -p "$HOME/.config"

# Link function
link_file() {
    local src="$1"
    local dest="$2"

    # If destination exists and is not a symlink, back it up
    if [[ -e "$dest" ]] && [[ ! -L "$dest" ]]; then
        warn "Backing up existing file: $dest"
        mv "$dest" "$dest.backup"
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

info "All symlinks created successfully!"
