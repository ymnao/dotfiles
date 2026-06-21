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

    # Homebrew 6 系は HOMEBREW_REQUIRE_TAP_TRUST 下で外部 tap を default で
    # 拒否するため brew bundle 前に trust を入れる。複数 tap になったら
    # Brewfile から ^tap 行を抽出して回す形に。
    brew trust --tap laishulu/homebrew >/dev/null || true

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
    # secretlint 13 系は Node 22+ を要求するため、pnpm 実行前に明示確認する。
    if ! command -v node &>/dev/null; then
        error "Node が見つかりません。brew install node を先に実行してください。"
    fi
    node_major=$(node --version | sed -E 's/^v([0-9]+)\..*/\1/')
    if [[ -z "$node_major" || "$node_major" -lt 22 ]]; then
        error "Node 22 以上が必要です (現在: $(node --version))"
    fi
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
