# Starship prompt
# `starship init fish | source` は starship 未インストール時に fish 起動を壊すため
# 存在ガードする (uv.fish と同じ `type -q` 形式に揃える)。
if type -q starship
    starship init fish | source
end
