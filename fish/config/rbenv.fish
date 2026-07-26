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
    # RBENV_ROOT の決定。既に設定されていれば尊重する (config.local.fish や
    # 親プロセスからの指定を潰さない。pnpm.fish の PNPM_HOME と同じ方針)。
    if not set -q RBENV_ROOT; or test -z "$RBENV_ROOT"
        # このマシンでは ruby の実体が Homebrew の keg 配下
        # ($HOMEBREW_PREFIX/opt/rbenv/versions) にあり、default root
        # (~/.rbenv/versions) は空。default root のままだと fish だけ system ruby に
        # フォールバックし、RBENV_ROOT を keg に向けている zsh (~/.zshrc、repo 管理外)
        # と ruby のバージョンが食い違う。
        #
        # 判定は「brew で rbenv を入れているか」ではなく「versions の実体がどちらに
        # あるか」で行う。ruby を標準の ~/.rbenv/versions に置く別マシンでは
        # keg 配下が空なのでこの分岐に入らず、default root がそのまま使われる。
        # (set への glob は一致 0 件でもエラーにならず空リストになる)
        set -l own_versions $HOME/.rbenv/versions/*
        set -l keg_versions $HOMEBREW_PREFIX/opt/rbenv/versions/*
        if test (count $own_versions) -eq 0; and test (count $keg_versions) -gt 0
            # HOMEBREW_PREFIX は config.fish の `brew shellenv fish` が export する。
            # ただし config.fish は /opt/homebrew 決め打ちなので、Intel mac や
            # Linuxbrew では export されない。その場合 keg_versions が空になり
            # ここには入らないため、default root のまま (PR 前と同じ挙動) になる。
            set -gx RBENV_ROOT $HOMEBREW_PREFIX/opt/rbenv
        end
    end
    rbenv init - fish | source
end
