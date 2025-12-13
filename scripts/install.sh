#!/usr/bin/env bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Get the dotfiles directory
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

info "Dotfiles directory: $DOTFILES_DIR"

# Detect OS
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
    *)
        error "Unsupported OS: $OS"
        ;;
esac

# Install Homebrew (macOS only)
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

# Create symlinks
info "Creating symlinks..."
bash "$DOTFILES_DIR/scripts/link.sh"

# Create local Git config if it doesn't exist (XDG-compliant)
mkdir -p "$HOME/.config/git"
if [[ ! -f "$HOME/.config/git/config.local" ]]; then
    warn "~/.config/git/config.local not found"
    info "Creating from template..."
    cp "$DOTFILES_DIR/git/config.local.template" "$HOME/.config/git/config.local"
    warn "Please edit ~/.config/git/config.local with your personal information"
fi

info "Installation complete!"
info "Please restart your shell or run: exec \$SHELL"
