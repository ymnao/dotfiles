# rbenv: Ruby バージョン管理
# init 出力を直書きせず動的に source する (starship.fish / zoxide.fish と同形式)。
# 「同形式」なのは書き方だけで起動コストは同等ではない: init 出力に
# `command rbenv rehash` が含まれるため fish 起動ごとにサブプロセスが 2 つ走る。
# 削るなら `rbenv init - --no-rehash fish` だが、shims の鮮度 (gem install 後の
# 実行ファイルを即反映) を優先して採らない。
#
# `init` の直後の `-` は必須。`-` を落とすと rbenv は「シェル初期化ファイルを
# 書き換える」モードになり、~/.config/fish は repo の fish/ への symlink なので
# tracked file が書き換わる。
#
# RBENV_ROOT は設定しない (default の ~/.rbenv を使う)。以前は ruby の実体が
# Homebrew の keg 配下にあったため RBENV_ROOT を keg に向けていたが、keg は
# `brew upgrade rbenv` で丸ごと消えるので配置自体が誤りだった (issue #219)。
# ruby を default root へ移したことで調整は不要になった。
if type -q rbenv
    rbenv init - fish | source
end
