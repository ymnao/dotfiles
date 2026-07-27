# nodebrew: Node バージョン切替
# rbenv / pyenv と違い `nodebrew init` 相当が無く、選択中バージョンの bin を
# PATH に足すだけ。サブプロセスを起こさないので起動コストはかからない。
#
# `-g` (fish_user_paths 経由) であることが要点。fish は fish_user_paths を
# PATH 全体の前に再構成するため、config.fish で先に走る `brew shellenv` が
# 入れた /opt/homebrew/bin より前に出る。これが無いと `brew "node"` の実体が
# 常に勝ち、`nodebrew use` の切替が PATH に反映されない。
# なお `-a` (append) にしても Homebrew より前に来る (順序が変わるのは
# fish_user_paths の中だけ) ので、brew node との優先順位を決めているのは
# prepend/append ではなく `-g` を使うこと自体。
# ~/.zshrc も nodebrew を prepend しており、これで shell 間の `node` が揃う
# (issue #218)。
#
# `test -d` ガードは張らない。fish_add_path は存在しないディレクトリを
# 黙って無視する (man: "If an argument is not an existing directory,
# fish_add_path ignores it")。メッセージ出力は全て verbose 時のみで、
# auto-verbose はプロンプトで直接叩いたときにしか発火しない (config から
# source した場合 `status current-command` は fish になる) ため、
# nodebrew 未インストールでも起動時に何も起きない。ガードを足しても
# 観測できる差が無い = 検証できないコードになるので置かない。
# fish_add_path は idempotent なので重複追加もされない (pnpm.fish と同じ方針)。
#
# NODEBREW_ROOT は設定も参照もしない。rbenv.fish / pyenv.fish の
# 「ROOT 変数を触らない」規約と同型 (root を keg 等に向けると
# `brew upgrade` で実体が消える。issue #219)。
fish_add_path -g $HOME/.nodebrew/current/bin
