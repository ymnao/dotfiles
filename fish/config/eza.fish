# eza: modern ls (exa の後継 active fork)
if type -q eza
    set -l base --group-directories-first
    set -l long -l $base --git --time-style=long-iso
    alias ls "eza $base"
    alias ll "eza $long"
    alias la "eza -a $long"
    alias lt "eza --tree --level=2 $base"
end
