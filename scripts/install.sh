#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"

# Dotfiles directory
DOTFILES_DIR="${SCRIPT_DIR%/*}"

info "Dotfiles directory: $DOTFILES_DIR"

# OS
OS="$(uname -s)"
case "$OS" in
    Darwin)
        info "Detected macOS"
        OS_TYPE="macos"
        ;;
    Linux)
        info "Detected Linux"
        OS_TYPE="linux"
        ;;
    CYGWIN*|MINGW*|MSYS*|Windows_NT)
        error "Windows detected. Please use PowerShell script instead:
    .\\scripts\\install.ps1

For detailed Windows setup instructions, see README.md"
        ;;
    *)
        error "Unsupported OS: $OS"
        ;;
esac

# Homebrew
if [[ "$OS_TYPE" == "macos" ]]; then
    if ! command -v brew &> /dev/null; then
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        info "Homebrew already installed"
    fi

    # Install packages from Brewfile
    if [[ -f "$DOTFILES_DIR/Brewfile" ]]; then
        info "Installing packages from Brewfile..."
        brew bundle install --file="$DOTFILES_DIR/Brewfile"
    fi
fi

# Symlinks
info "Creating symlinks..."
bash "$DOTFILES_DIR/scripts/link.sh"

# Node tooling (secretlint 等)
if [[ -f "$DOTFILES_DIR/package.json" ]] && command -v pnpm &>/dev/null; then
    info "Installing Node dev deps via pnpm..."
    (cd "$DOTFILES_DIR" && pnpm install)
fi

# Local Git config
mkdir -p "$HOME/.config/git"
if [[ ! -f "$HOME/.config/git/config.local" ]]; then
    warn "$HOME/.config/git/config.local not found"
    info "Creating from template..."
    cp "$DOTFILES_DIR/git/config.local.template" "$HOME/.config/git/config.local"
    warn "Please edit ~/.config/git/config.local with your personal information"
fi

info "Installation complete!"
info "Please restart your shell or run: exec \$SHELL"
