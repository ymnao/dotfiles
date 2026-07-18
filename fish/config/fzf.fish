# fzf: fisher 不要の native fish 統合 (fzf 0.48+ 同梱)
# キーバインド: Ctrl-R history / Ctrl-T file / Alt-C cd
if type -q fzf
    fzf --fish | source

    # fd を default finder に (.gitignore を尊重、hidden も対象)
    set -l fd_base --hidden --follow --exclude .git
    set -gx FZF_DEFAULT_COMMAND "fd --type f $fd_base"
    set -gx FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND
    set -gx FZF_ALT_C_COMMAND "fd --type d $fd_base"

    # preview: bat があれば syntax highlight
    if type -q bat
        set -gx FZF_CTRL_T_OPTS "--preview 'bat --color=always --style=numbers --line-range=:200 {}'"
    end
end
