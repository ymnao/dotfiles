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
# RBENV_ROOT は設定せず default root (~/.rbenv) に任せる。
# **前提: RBENV_ROOT を外部 (~/.zshrc 等) で export しないこと。** keg
# ($(brew --prefix rbenv)) を root にすると ruby の実体が keg 内に入り
# `brew upgrade rbenv` で丸ごと消える (issue #219)。ここで RBENV_ROOT を
# 補正しないのは、その配置を追認する装置を残さないため。
# default root に ruby が無いマシンでは rbenv が **エラーを出さずに** system
# ruby へフォールバックする。復旧手順は 3 つ揃って初めて完了する:
#   1. `rbenv install <version>` — default root に本体を入れる。keg からの
#      コピーでは直らない: bin/ruby と全 .bundle の Mach-O ロードパスが
#      $(brew --prefix rbenv)/versions/... を絶対参照しており、upgrade 後は
#      その versions/ ごと消えて dyld が解決できなくなる (shebang の sed
#      書き換えでは届かない)
#   2. `rbenv global <version>` — $RBENV_ROOT/version は keg 側にあったので
#      一緒に失われる。これが無いと 1 の後も system ruby のまま
#   3. gem の再導入 — gem も keg 配下の versions/ と一緒に消える
if type -q rbenv
    rbenv init - fish | source
end
