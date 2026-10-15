#!/bin/bash
# claude.ai/code のクラウド environment の setup script から呼ぶ。
# environment 側には次の 2 行だけを置き、届けるものはこのファイルで管理する:
#   git clone --depth 1 https://github.com/ymnao/dotfiles.git /opt/dotfiles || true
#   bash /opt/dotfiles/claude/cloud-setup.sh || true
# setup script の結果はキャッシュされるので、main の変更が届くのは約 7 日ごとの作り直しか、setup script を変更したとき。
# claude/skills/ を丸ごと届けないのは、write-issue 以外の skill がクラウドに無い hook やローカル環境に依存するため。
set -euo pipefail

mkdir -p "$HOME/.claude/skills"
ln -sfn /opt/dotfiles/claude/skills/write-issue "$HOME/.claude/skills/write-issue"
