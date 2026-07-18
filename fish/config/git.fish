# Git abbreviations
# fish abbr は space/enter で展開されるため、履歴に元コマンドが残り alias より読みやすい。
# AGENTS.md の Shell 環境ルールで alias 禁止としているためこちらに寄せる。

abbr -a g git
abbr -a gs git status
abbr -a gd git diff
abbr -a gds git diff --staged
abbr -a ga git add
abbr -a gc git commit
abbr -a gcm git commit -m
abbr -a gco git checkout
abbr -a gsw git switch
abbr -a gb git branch
abbr -a gl git log --oneline -20
abbr -a gp git push
abbr -a gpl git pull
abbr -a gf git fetch
