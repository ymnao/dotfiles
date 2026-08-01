#!/usr/bin/env bash
#
# SessionStart hook (Claude Code, matcher: compact): コンパクション直後に
# 作業状態のリマインダーを注入する。
# 正本: agents/hooks/session-compact-context.sh
#
# 背景: コンパクション後も CLAUDE.md / rules は残るが、「セッション中の
# 作業状態」(ブランチ・未コミット変更・直近の流れ) は要約で薄まりやすい。
# stdout に出した内容はコンテキストに追加されるので、決定的な git 情報だけを
# 短く再注入する。CLAUDE.md の内容は重複になるため注入しない。
#
# fail-open: git リポジトリ外・git/jq 不在では何も出さず exit 0。
#
# stdout の先頭行は `[` / `{` で始めない (issue #240)。codex は hook の stdout が
# その 2 文字で始まると JSON 出力とみなし、パースに失敗した時点で本文を model の
# context に入れない (実測根拠は docs/ai-operations.md §10)。横断検査は
# scripts/lint-hook-stdout.sh、この hook 固有の先頭行 pin は
# tests/session-compact/run-session-compact-tests.sh にある。

set -uo pipefail

input=$(cat)

command -v git >/dev/null 2>&1 || exit 0

cwd=""
if command -v jq >/dev/null 2>&1; then
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null) || cwd=""
fi
[ -n "$cwd" ] || cwd=$(pwd -P)
[ -d "$cwd" ] || exit 0

root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0

branch=$(git -C "$root" branch --show-current 2>/dev/null)
porcelain=$(git -C "$root" status --porcelain 2>/dev/null)
dirty_count=0
[ -n "$porcelain" ] && dirty_count=$(printf '%s\n' "$porcelain" | grep -c . || true)
recent=$(git -C "$root" log --oneline -3 2>/dev/null)

cat <<EOF
session-compact-context: コンパクション後の作業状態リマインダー
- リポジトリ: $root
- ブランチ: ${branch:-(detached HEAD)}
- 未コミット変更: ${dirty_count} 件
EOF
if [ -n "$porcelain" ]; then
  printf '%s\n' "$porcelain" | head -10
fi
if [ -n "$recent" ]; then
  echo "- 直近のコミット:"
  printf '%s\n' "$recent"
fi
exit 0
