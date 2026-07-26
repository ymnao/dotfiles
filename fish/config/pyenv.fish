# pyenv: Python バージョン管理
# init 出力には Cellar のバージョン付き絶対パス (completions) が埋まり
# `brew upgrade pyenv` で壊れるため、直書きせず動的に source する
# (starship.fish / zoxide.fish と同形式)。ただし「同形式」なのは書き方だけで
# 起動コストは同等ではない: init 出力に `command pyenv rehash` と Cellar 配下
# completions の source が含まれるため、fish 起動ごとにサブプロセスが 2 つ走る
# (rbenv 側に completions の分は無い)。削るなら `pyenv init - --no-rehash fish`
# だが、shims の鮮度 (pip 等が入れた実行ファイルを即反映) を優先して採らない。
# PYENV_ROOT は設定しない (rbenv.fish と同じく default root を使う)。
# uv (uv.fish) とは役割が重複しうるが、UV_PYTHON_PREFERENCE=only-managed により
# uv は pyenv の shims を参照しないため干渉しない
if type -q pyenv
    pyenv init - fish | source
end
