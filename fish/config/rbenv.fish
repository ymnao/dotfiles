# rbenv: Ruby バージョン管理
# init 出力を直書きせず動的に source する (starship.fish / zoxide.fish と同形式)。
# RBENV_ROOT は default (~/.rbenv) を使い、zsh 側の `brew --prefix rbenv` 上書きには
# 追随しない (起動ごとの brew サブプロセスコストと非標準 root を避けるため)
if type -q rbenv
    rbenv init - fish | source
end
