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

# assert_tier <name> <expected-tier> — カレントブランチの分類結果を assert
# (scenario / 削除シナリオ両方から呼ぶ共通アサート)
assert_tier() {
  local name="$1" want="$2" got tier
  got=$(bash "$CLASSIFIER" main)
  tier=$(printf '%s' "$got" | jq -r '.tier')
  if [ "$tier" = "$want" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $name: expected=$want got=$tier ($got)"
    fail=$((fail + 1))
  fi
}

# scenario <name> <expected-tier> — stdin に「作るファイル相対パス<TAB>内容」を行区切りで受ける
scenario() {
  local name="$1" want="$2" path content
  git checkout -q main
  git checkout -qb "case-$name"
  while IFS=$(printf '\t') read -r path content; do
    [ -n "$path" ] || continue
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
    git add "$path"
  done
  git commit -qm "case: $name"
  assert_tier "$name" "$want"
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

scenario bun-text-lockfile high <<EOF
bun.lock${T}{}
EOF

scenario poetry-lockfile high <<EOF
poetry.lock${T}[[package]]
EOF

# --- テスト削除シグナル (2026-07-07 追加) ---
# ここから下は削除シナリオ専用。base 側にテスト fixture を仕込む必要があり、
# main を汚染するため以降に scenario() を追記しないこと (base tree が変わり
# 既存 scenario と結果が変わる)。追加シナリオは上の scenario 群に足すこと
git checkout -q main
mkdir -p tests __tests__ spec src fixtures
printf 'assert 1\n' > tests/util_test.py
printf 'export const t = 1\n' > __tests__/foo.js
printf 'describe "x"\n' > spec/foo.rb
printf 'test\n' > src/foo.test.ts
printf 'test\n' > src/foo.spec.ts
printf '{}\n' > fixtures/example.cases.jsonl
printf 'x = 1\n' > src/keep.py
git add tests __tests__ spec src fixtures && git commit -qm "add test fixture"

# テストファイル削除 → high (削除 ERE の各分岐)
git checkout -qb case-test-removal
git rm -q tests/util_test.py
git commit -qm "remove test"
assert_tier test-removal high

git checkout -q main
git checkout -qb case-jest-removal
git rm -q __tests__/foo.js
git commit -qm "remove jest test"
assert_tier __tests__-removal high

git checkout -q main
git checkout -qb case-spec-removal
git rm -q spec/foo.rb
git commit -qm "remove spec"
assert_tier spec-removal high

git checkout -q main
git checkout -qb case-dot-test-removal
git rm -q src/foo.test.ts
git commit -qm "remove .test.ts"
assert_tier dot-test-removal high

git checkout -q main
git checkout -qb case-dot-spec-removal
git rm -q src/foo.spec.ts
git commit -qm "remove .spec.ts"
assert_tier dot-spec-removal high

git checkout -q main
git checkout -qb case-cases-jsonl-removal
git rm -q fixtures/example.cases.jsonl
git commit -qm "remove cases jsonl"
assert_tier cases-jsonl-removal high

# テストファイルの変更 (削除でない) → check_deleted は発火しない
git checkout -q main
git checkout -qb case-test-modify
printf 'assert 2\n' >> tests/util_test.py
git commit -qam "modify test"
assert_tier test-modify medium

# 削除 ERE 対象パターンのファイルを「変更」しても high にならない (誤検知しない)
git checkout -q main
git checkout -qb case-dot-test-modify
printf 'more\n' >> src/foo.test.ts
git commit -qam "modify .test.ts"
assert_tier dot-test-modify medium

# テスト以外のファイル削除 → high にしない (通常 tier)
git checkout -q main
git checkout -qb case-src-removal
git rm -q src/keep.py
git commit -qm "remove src"
assert_tier non-test-removal medium

echo "classify-risk tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
