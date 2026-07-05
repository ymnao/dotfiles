#!/usr/bin/env bash
set -euo pipefail

# skill-eval-sandbox リポジトリの初期化 (冪等)。
# 前提: gh 認証済み・sandbox リポジトリの clone 内 (cwd) で実行する。

if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then
  echo "ERROR: run inside the skill-eval-sandbox clone" >&2
  exit 1
fi

repo_name=$(gh repo view --json name --jq '.name')
if [ "$repo_name" != "skill-eval-sandbox" ]; then
  echo "ERROR: this does not look like skill-eval-sandbox (got: $repo_name). Aborting for safety." >&2
  exit 1
fi

# 初期コミット
if [ ! -f README.md ]; then
  echo "# skill-eval-sandbox" > README.md
  mkdir -p src
  printf 'export const add = (a, b) => a + b\n' > src/util.js
  git add . && git commit -m "chore: seed sandbox" && git push -u origin HEAD
fi

# ラベル (存在すればスキップ)
gh label create bug --color d73a4a 2>/dev/null || true
gh label create documentation --color 0075ca 2>/dev/null || true
gh label create refactor --color a2eeef 2>/dev/null || true

# eval 用 issue (タイトルで冪等判定)
ensure_issue() {
  local title="$1" label="$2"
  if [ -z "$(gh issue list --search "$title in:title" --state all --json number --jq '.[0].number // empty')" ]; then
    if [ -n "$label" ]; then
      gh issue create --title "$title" --body "eval fixture" --label "$label"
    else
      gh issue create --title "$title" --body "eval fixture"
    fi
  fi
}
ensure_issue "eval: login redirect loop" "bug"
ensure_issue "eval: update setup docs" "documentation"
ensure_issue "eval: add user preferences" ""
ensure_issue "eval: closed issue fixture" ""
closed_num=$(gh issue list --search "eval: closed issue fixture in:title" --state open --json number --jq '.[0].number // empty')
[ -n "$closed_num" ] && gh issue close "$closed_num"

echo "sandbox seeded."
