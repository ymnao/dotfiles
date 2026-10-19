#!/usr/bin/env bash
set -euo pipefail

# /new-project のローカル側チェック。新しい repo が開発を始められる状態かを
# 項目ごとに OK / NG で出し、NG が 1 つでもあれば exit 1。
#
# GitHub 側 (ruleset・ラベル) はここでは見ない。Claude Code の Bash tool から
# bash 経由で GitHub CLI を呼ぶと Keychain の認証が切れて必ず失敗するため、
# その確認は SKILL.md の check 節で単独のコマンドとして打つ。
#
# Usage: check-ready.sh [<dir>]   (既定はカレントディレクトリ)

dir="${1:-.}"
if [ ! -d "$dir" ]; then
  echo "ERROR: directory not found: $dir" >&2
  exit 2
fi

ng=0

report() {
  local ok="$1" item="$2" hint="$3"
  if [ "$ok" -eq 1 ]; then
    printf 'OK  %s\n' "$item"
  else
    printf 'NG  %s — %s\n' "$item" "$hint"
    ng=1
  fi
}

found=0
[ -f "$dir/CLAUDE.md" ] && found=1
report "$found" "CLAUDE.md" "claude-init.sh でテンプレートをコピーする"

found=0
for f in "$dir"/.github/workflows/*.yml "$dir"/.github/workflows/*.yaml; do
  if [ -f "$f" ]; then
    found=1
    break
  fi
done
report "$found" ".github/workflows/ の workflow" "lint / test を実行する ci.yml を置く"

found=0
[ -f "$dir/.gitignore" ] && grep -Fxq '.claude/settings.local.json' "$dir/.gitignore" && found=1
report "$found" ".gitignore の .claude/settings.local.json" "claude-init.sh が追記する行が無い"

exit "$ng"
