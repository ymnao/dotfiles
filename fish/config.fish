# Fish shell configuration

# XDG Base Directory
set -gx XDG_CONFIG_HOME $HOME/.config
set -gx XDG_DATA_HOME $HOME/.local/share
set -gx XDG_CACHE_HOME $HOME/.cache
set -gx XDG_STATE_HOME $HOME/.local/state

# Editor
set -gx EDITOR nvim
set -gx VISUAL nvim
set -gx GIT_EDITOR nvim

# Pager
set -gx PAGER less
set -gx MANPAGER "nvim +Man!"

# History (Fish manages history size automatically, no configuration needed)

# Path additions (fish_add_path is idempotent - won't add duplicates)
fish_add_path -g $HOME/.local/bin
fish_add_path -g $HOME/bin

# Homebrew
if test -e /opt/homebrew/bin/brew
    /opt/homebrew/bin/brew shellenv fish | source
end

# Local configuration
if test -f $XDG_CONFIG_HOME/fish/config.local.fish
    source $XDG_CONFIG_HOME/fish/config.local.fish
end

# Additional configurations
for file in $XDG_CONFIG_HOME/fish/config/*.fish
    source $file
end

# Suppress greeting
set fish_greeting

# Added by LM Studio CLI (lms)
# ユーザーホーム非依存化: `~/.lmstudio/bin` があるときだけ追加する。
# begin/end マーカー行の文言は LMStudio installer が再検出に使うため保持
# (再インストール時の重複追記を防ぐ)。
if test -d $HOME/.lmstudio/bin
    fish_add_path -g $HOME/.lmstudio/bin
end
# End of LM Studio CLI section

