# zoxide: frecency 学習型 cd
# --cmd cd で cd 自体を置き換え (部分マッチで飛べる、通常 cd の挙動も透過維持)
if type -q zoxide
    zoxide init fish --cmd cd | source
end
