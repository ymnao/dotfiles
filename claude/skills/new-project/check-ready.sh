#!/usr/bin/env bash
set -euo pipefail

# /new-project のローカル側チェック。新しい repo が開発を始められる状態かを
# 項目ごとに OK / NG で出し、NG が 1 つでもあれば exit 1。
#
# GitHub 側 (ruleset・ラベル) はここでは見ない。Claude Code の Bash tool から
# bash 経由で GitHub CLI を呼ぶと Keychain の認証が切れて必ず失敗するため、
# その確認は SKILL.md の step 6 で単独のコマンドとして打つ。
#
# Usage: check-ready.sh [<dir>]   (既定はカレントディレクトリ)

dir="${1:-.}"
if [ ! -d "$dir" ]; then
  echo "ERROR: directory not found: $dir" >&2
  exit 2
fi

ng=0

# Usage: check <項目> <NG のときの直し方> <コマンド...>
check() {
  local item="$1" hint="$2"
  shift 2
  if "$@"; then
    printf 'OK  %s\n' "$item"
  else
    printf 'NG  %s — %s\n' "$item" "$hint"
    ng=1
  fi
}

# *.yml という名前のディレクトリは workflow として数えない
has_workflow() {
  local f
  for f in "$dir"/.github/workflows/*.yml "$dir"/.github/workflows/*.yaml; do
    [ -f "$f" ] && return 0
  done
  return 1
}

check "CLAUDE.md" "claude-init.sh でテンプレートをコピーする" \
  test -f "$dir/CLAUDE.md"
check ".github/workflows/ の workflow" "lint / test を実行する ci.yml を置く" \
  has_workflow
check ".gitignore の .claude/settings.local.json" "claude-init.sh が追記する行が無い" \
  grep -Fxqs '.claude/settings.local.json' "$dir/.gitignore"

exit "$ng"
