# ========================================
# Core Tools
# ========================================
brew "git"
brew "git-delta"
brew "gh"
brew "lazygit"
brew "neovim"
brew "fish"
brew "ripgrep"
brew "fd"
brew "tree"
# brew "p7zip"  # Excluded due to known archive extraction vulnerabilities
                # Use macOS built-in compression or The Unarchiver instead

# ========================================
# Development Languages & Tools
# ========================================
brew "go"
brew "golangci-lint"
brew "pyenv"
brew "uv"
brew "nodebrew"
# nodebrew は version 切替ツール。常用 Node 本体は brew "node" で導入する
# (secretlint 13 や devDependencies が Node 22+ を要求するため)。
brew "node"
brew "pnpm"
brew "rbenv"
brew "ruby-build"
brew "rust"
brew "gcc"
brew "openjdk@11"
brew "openjdk@17"

# ========================================
# AWS Development
# ========================================
brew "aws-sam-cli"
brew "awscli"

# ========================================
# React Native / Mobile Development
# ========================================
brew "watchman"

# ========================================
# Media & Utilities
# ========================================
brew "ffmpeg"
brew "imagemagick"
brew "nkf"

# ========================================
# Input Method
# ========================================
# macism は brew/core になく laishulu/homebrew tap から配信されている。
# tap 宣言なしだと brew bundle が formula 解決に失敗して中断する。
tap "laishulu/homebrew"
brew "macism"

# ========================================
# Remote Access (Phase 0)
# ========================================
# Tailscale は macOS 公式推奨の GUI 版 (cask) を使う。CLI 版 (brew "tailscale") は
# tailscaled デーモンを別途起動する必要があり、新規環境でつまづきやすいため避ける。
cask "tailscale-app"
brew "mosh"
brew "tmux"
brew "ntfy"

# ========================================
# Dependencies (auto-installed by other packages)
# ========================================
brew "openssl@3"
brew "readline", link: true
brew "gmp"
brew "pkgconf"

# ========================================
# GUI Applications
# ========================================
cask "alfred"
cask "wezterm"
cask "google-chrome"
cask "visual-studio-code"
cask "slack"
cask "zoom"
cask "postman"
cask "claude-code"
cask "codex"
cask "lm-studio"

# ========================================
# Fonts
# ========================================
cask "font-jetbrains-mono-nerd-font"
cask "font-cica"
cask "font-udev-gothic"

# ========================================
# Go Tools
# ========================================
go "golang.org/x/tools/cmd/goimports"
go "golang.org/x/tools/gopls"
go "honnef.co/go/tools/cmd/staticcheck"
