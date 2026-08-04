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
# brew "p7zip"  # Excluded due to known archive extraction vulnerabilities
                # Use macOS built-in compression or The Unarchiver instead

# ========================================
# Modern CLI Utilities
# ========================================
# fish native 統合や alias は fish/config/*.fish 側で定義する。
brew "fzf"  # 対話型ファジー検索 (fish 統合は `fzf --fish | source`、0.48+)
brew "zoxide"  # frecency 学習型 cd。`zoxide init fish --cmd cd` で cd を置き換え
brew "eza"  # modern ls (git status 統合、tree、group-directories-first)
brew "bat"  # cat + syntax highlight (sharkdp 製、fzf preview で使用)
# herdr = コーディングエージェント用のターミナル multiplexer (agent 版 tmux)。
# 設定は herdr/config.toml、Claude Code 統合は claude/hooks/herdr-agent-state.sh。
# issue #265 で評価中 — 定着しなければこの行と herdr/ ごと revert する。
# 常駐化 (brew services start herdr) は意図的に有効化していない。
brew "herdr"

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
# ただし `nodebrew use` 済みの環境では fish/config/nodebrew.fish が
# ~/.nodebrew/current/bin を Homebrew より前に置くため、実際に起動する node は
# nodebrew 側になる (zsh も同じ)。どちらが使われているかは `command -v node`
# で確認できる。`make lint` は PATH 先頭の node で動くので、nodebrew 側を
# 古い版に切り替えると壊れる点に注意。効いている下限は secretlint 13 の
# engines (>=22.0.0) ではなく pnpm 11 の方で、v22.13 未満は pnpm が exit 1
# する (現在の nodebrew は v22.14.0 なので余裕は 0.1 マイナー)。
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
brew "jq"  # Makefile / hooks / statusline が command -v jq で hard-fail

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
brew "marp-cli"
brew "nkf"
brew "mecab-ipadic"
# figlet / poppler は主に agent (Claude Code / codex) の Bash 経由で叩くため
# shell history に痕跡が残らない (2026-07-30 時点で zsh / fish とも 0 ヒット)。
# 棚卸しで history のヒット 0 件をこの 2 つの未使用の根拠にしないこと。
brew "figlet"  # ASCII art バナー生成 (ymnao プロジェクトのロゴ生成で使用)
brew "poppler"  # pdftotext 等の PDF テキスト抽出 (論文 PDF の読み取りで使用)
# TeX Live 本体。uplatex / platex を直接使用 (2026-07-30 時点の zsh history に
# uplatex 27 行 / platex 単独 5 行)、paper-review skill は latexmk をビルド既定の
# フォールバックにしている。
# ディスク実測 (2026-07-30、du -sh): /usr/local/texlive/2026 が 9.7GiB、加えて
# Caskroom にインストーラ pkg が 6.4GiB 残るので計 16.1GiB。Brewfile 中で単一項目
# としては最大 (make install の所要時間への寄与は未計測)。
# また pkg artifact の cask なので install に sudo のパスワード入力を伴う。ここで
# 失敗すると scripts/install.sh は set -euo pipefail のため symlink 作成前に中断する。
# make update 側の追加 DL は auto_updates 無しのため cask 新版が出た回のみ。
# LaTeX を書かないマシンでは Brewfile を編集せず、環境変数で除外する:
#   HOMEBREW_BUNDLE_CASK_SKIP=mactex-no-gui make install
# この変数は brew bundle check も見るため、make update でも同じ指定が要る
# (未指定だと Makefile の check が未インストール扱いで hard-fail する)。
cask "mactex-no-gui"

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
# pyenv の Python 3.10.13 が /opt/homebrew/opt/gdbm/lib/libgdbm.6.dylib に直リンク
# している (otool -L で確認)。Homebrew の依存グラフからは見えないため、依存元の
# formula を消すと autoremove の巻き添えで消え、pyenv 側の dbm.gnu / dbm.ndbm が
# ImportError になる (2026-07-30 に python@3.10 の uninstall で実際に踏んだ)。
# 明示的に記載して autoremove の対象から外す。
brew "gdbm"

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
# kura は自作の menu bar app。HOMEBREW_REQUIRE_TAP_TRUST 下でも通るよう trusted: true。
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
