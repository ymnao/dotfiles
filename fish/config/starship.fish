# Starship prompt
# `starship init fish | source` は starship 未インストール時に fish 起動を壊すため
# command -q でガードする。
if command -q starship
    starship init fish | source
end
