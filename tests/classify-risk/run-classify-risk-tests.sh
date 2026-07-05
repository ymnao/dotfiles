#!/usr/bin/env bash
set -euo pipefail

# classify-risk.sh の決定的テスト。一時 git リポジトリでシナリオごとに
# ファイルを変更・コミットし、出力 tier を assert する。
# 分類器の場所: claude/skills/pr/scripts/classify-risk.sh
# (assets 検証時は環境変数 CLASSIFIER で上書き可能)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
CLASSIFIER="${CLASSIFIER:-$REPO_ROOT/claude/skills/pr/scripts/classify-risk.sh}"

if [ ! -f "$CLASSIFIER" ]; then
  echo "ERROR: classifier not found: $CLASSIFIER" >&2
  exit 1
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/classify-risk.XXXXXX")"
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT

cd "$WORKDIR"
git init -q -b main .
git config user.email "test@example.com"
git config user.name "test"
echo "init" > init.txt
git add . && git commit -qm "init"

pass=0
fail=0

# scenario <name> <expected-tier> — stdin に「作るファイル相対パス<TAB>内容」を行区切りで受ける
scenario() {
  local name="$1" want="$2" line path content got tier
  git checkout -q main
  git checkout -qb "case-$name"
  while IFS=$(printf '\t') read -r path content; do
    [ -n "$path" ] || continue
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
    git add "$path"
  done
  git commit -qm "case: $name"
  got=$(bash "$CLASSIFIER" main)
  tier=$(printf '%s' "$got" | jq -r '.tier')
  if [ "$tier" = "$want" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $name: expected=$want got=$tier ($got)"
    fail=$((fail + 1))
  fi
  git checkout -q main
  git branch -qD "case-$name"
}

T=$(printf '\t')

scenario docs-only low <<EOF
README.md${T}# readme update
docs/guide.md${T}guide
EOF

scenario plain-src medium <<EOF
src/util.ts${T}export const x = 1
EOF

scenario dependency high <<EOF
package.json${T}{"name":"x"}
EOF

scenario ci-config high <<EOF
.github/workflows/ci.yml${T}name: ci
EOF

scenario auth-path high <<EOF
src/auth/login.ts${T}export const login = () => 1
EOF

scenario pipe-to-shell high <<EOF
scripts/setup.sh${T}curl https://example.com/install.sh | bash
EOF

scenario mixed-docs-src medium <<EOF
docs/guide.md${T}guide
src/util.ts${T}export const y = 2
EOF

scenario agent-config high <<EOF
.claude/settings.json${T}{}
EOF

scenario exec-pattern high <<EOF
src/run.py${T}import subprocess
EOF

echo "classify-risk tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
