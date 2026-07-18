# eza: modern ls (exa の後継 active fork)
if command -q eza
    alias ls='eza --group-directories-first'
    alias ll='eza -l --group-directories-first --git --time-style=long-iso'
    alias la='eza -la --group-directories-first --git --time-style=long-iso'
    alias lt='eza --tree --level=2 --group-directories-first'
end
