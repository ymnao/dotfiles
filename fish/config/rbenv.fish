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
if type -q rbenv
    # 実体の ruby は Homebrew keg 配下 ($HOMEBREW_PREFIX/opt/rbenv/versions) にあり、
    # default root (~/.rbenv) は空。zsh 側 (~/.zshrc、repo 管理外) が RBENV_ROOT を
    # 同じ場所に向けているので fish も揃える。揃えないと fish だけ system ruby に
    # フォールバックし、shell 間で ruby のバージョンが食い違う。
    # HOMEBREW_PREFIX は config.fish の `brew shellenv fish` が既に export しているので
    # ここで brew を再実行するコストはかからない。
    if set -q HOMEBREW_PREFIX; and test -d $HOMEBREW_PREFIX/opt/rbenv
        set -gx RBENV_ROOT $HOMEBREW_PREFIX/opt/rbenv
    end
    rbenv init - fish | source
end
