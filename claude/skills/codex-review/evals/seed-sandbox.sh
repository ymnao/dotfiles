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

# 初期コミット。現存する eval (dev/08) は README.md への doc 追記から
# PR を作るだけなので、ラベル / issue の seed は不要 (issue #263 で削除)。
if [ ! -f README.md ]; then
  echo "# skill-eval-sandbox" > README.md
  git add . && git commit -m "chore: seed sandbox" && git push -u origin HEAD
fi

echo "sandbox seeded."
