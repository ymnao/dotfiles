# ========================================
# Core Tools
# ========================================
brew "git"
brew "git-delta"
brew "git-filter-repo"
brew "gh"
brew "lazygit"
brew "neovim"
brew "tree-sitter-cli"
brew "fish"
brew "starship"  # cross-shell prompt (fish から init して使用。pwsh 未配線)
brew "ripgrep"
brew "fd"
brew "tree"
brew "tmux"  # ローカル terminal multiplexer (リモート用ではない)
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
# Code Quality & Linters
# ========================================
brew "shellcheck"
brew "actionlint"

# ========================================
# AWS Development
# ========================================
brew "aws-sam-cli"
brew "awscli"

# ========================================
# Database & Backend
# ========================================
# supabase は公式 tap から配信。macism と同様、trusted: true で
# HOMEBREW_REQUIRE_TAP_TRUST 下でも bundle install が通るようにする。
tap "supabase/tap"
brew "supabase/tap/supabase", trusted: true

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
brew "marp-cli"
brew "mecab-ipadic"

# ========================================
# Security
# ========================================
brew "gnupg"

# ========================================
# Input Method
# ========================================
# macism は brew/core になく laishulu/homebrew tap から配信されている。
# Homebrew 6 の HOMEBREW_REQUIRE_TAP_TRUST 下でも brew bundle install が
# 単独で通るよう trusted: true を付与する (tap 全体ではなく formula 単位で
# 信頼)。これにより install.sh 側で brew trust を別途叩く必要がなくなる。
tap "laishulu/homebrew"
brew "laishulu/homebrew/macism", trusted: true

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
cask "warp"
cask "google-chrome"
cask "visual-studio-code"
cask "cursor"
cask "slack"
cask "zoom"
cask "postman"
cask "claude"
cask "claude-code"
cask "codex"
cask "codex-app"
tap "ymnao/homebrew-tap"
cask "ymnao/homebrew-tap/kura", trusted: true

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
