# bat: cat + syntax highlight
# MANPAGER は config.fish で nvim +Man! に設定済みなので触らない
if type -q bat
    set -gx BAT_THEME "Monokai Extended"
end
