# pyenv: Python バージョン管理
# init 出力には Cellar のバージョン付き絶対パス (completions) が埋まり
# `brew upgrade pyenv` で壊れるため、直書きせず動的に source する
# (starship.fish / zoxide.fish と同形式)。
# uv (uv.fish) とは役割が重複しうるが、UV_PYTHON_PREFERENCE=only-managed により
# uv は pyenv の shims を参照しないため干渉しない
if type -q pyenv
    pyenv init - fish | source
end
