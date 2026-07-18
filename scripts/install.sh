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

    # mecab-ipadic は Caveats で mecabrc への dicdir 追記を要求する。
    # brew bundle は Caveats を実行しないため、辞書が読めない状態で残る。
    # 有効な (コメントアウトされていない) dicdir が無ければ追記する。
    # (`brew --prefix <formula>` は未インストール時に非ゼロで存在チェックを兼ねる)
    if brew --prefix mecab-ipadic >/dev/null 2>&1; then
        brew_prefix="$(brew --prefix)"
        mecabrc="$brew_prefix/etc/mecabrc"
        dicdir_path="$brew_prefix/lib/mecab/dic/ipadic"
        if [[ -f "$mecabrc" ]] && ! grep -Eq '^[[:space:]]*dicdir[[:space:]]*=' "$mecabrc"; then
            info "Configuring mecabrc dicdir: $dicdir_path"
            printf 'dicdir = %s\n' "$dicdir_path" >> "$mecabrc"
        fi
    fi

    # tealdeer は初回のみ tldr cache を取得する必要がある。
    # brew bundle は Caveats を実行しないため、cache 未取得時に初期化する。
    # `tldr --list` は cache 未取得だと非ゼロで返るので存在チェックに使う。
    if brew --prefix tealdeer >/dev/null 2>&1; then
        if ! tldr --list >/dev/null 2>&1; then
            info "Initializing tealdeer cache: tldr --update"
            tldr --update || true
        fi
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
