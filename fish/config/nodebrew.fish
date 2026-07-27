# nodebrew: Node バージョン切替
# rbenv / pyenv と違い `nodebrew init` 相当が無く、選択中バージョンの bin を
# PATH に足すだけ。サブプロセスを起こさないので起動コストはかからない。
#
# `brew "node"` の実体より前に出るので、`nodebrew use` の切替が PATH に
# 反映される (issue #218)。前に出る理由は config.fish の実行順で、この
# ファイル自体の書き方ではない: `brew shellenv` (/opt/homebrew/bin を PATH
# 先頭に置く) が先に走り、config/*.fish のループはその後なので、後から
# prepend する側が勝つ。`-a` (append) にしても Homebrew との前後は変わらない
# (順序が変わるのは fish_user_paths の中だけ)。
#
# `-g` は別の役割で load-bearing。スコープ指定を省くと fish_add_path は
# **universal** を既定にするため ~/.config/fish/fish_variables が書かれ、
# repo 管理外の永続状態ができる (この行を消しても PATH に残り続ける)。
# `-g` なら global 変数で、shell を閉じれば消える。
#
# zsh 側 (~/.zshrc) にも同等の prepend が要るが、それは repo 管理外の
# ファイルなのでここでは保証しない。「shell 間で揃っている」と読まないこと —
# 揃うかどうかは ~/.zshrc の現況次第で、この repo に検出の契機は無い。
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
# NODEBREW_ROOT は参照せず既定 root (~/.nodebrew) を直接書く。rbenv.fish /
# pyenv.fish の「ROOT 変数を触らない」と字面は似ているが同型ではない:
# あちらは root の解決を `<tool> init` 本体に委ねるので user 設定が生きる。
# こちらはパスを持つので、NODEBREW_ROOT を設定した環境では
# ~/.nodebrew/current/bin が無く**無言で配線されない** (issue #218 と同じ
# 症状が再発する)。既定 root 前提で足りているので参照を足さない、という
# 割り切り。root を移すときはここも直すこと。
fish_add_path -g $HOME/.nodebrew/current/bin
