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

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq not installed (Brewfile: brew install jq)" >&2
  exit 1
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/classify-risk.XXXXXX")"
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT

cd "$WORKDIR"
git init -q -b main .
git config user.email "test@example.com"
git config user.name "test"
# rename 検出を明示 ON にして、host の diff.renames グローバル設定に依存しない
# (rename は check_deleted の --diff-filter=D から除外されるため挙動が変わる)
git config diff.renames true
echo "init" > init.txt
git add . && git commit -qm "init"
# 削除シナリオが main を汚染しない基準点として init sha を保持する
INITIAL_MAIN_SHA=$(git rev-parse HEAD)

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
  local name="$1" want="$2" path content line
  git checkout -q main
  git checkout -qb "case-$name"
  # タブ分解は cut で行う。IFS=$(printf '\t') read はタブが空白系 IFS の
  # ため連続タブ (空フィールド) を潰し、将来 fixture が leading tab や空
  # path 形式に拡張された時に content が path 位置に昇格して誤テストが
  # silently PASS するリスクがある (verify-ci hook で修正済みバグの同型)。
  # タブ無し行では cut -f2- が行全体を返してしまうため、tab 有無を明示
  # 判定して content を分岐する (旧 read 実装は content="" になっていた)。
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    path=$(printf '%s' "$line" | cut -f1)
    case "$line" in
      *"$(printf '\t')"*) content=$(printf '%s' "$line" | cut -f2-) ;;
      *) content="" ;;
    esac
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
# 削除シナリオは main 側に fixture を必要とするが、各ケースの直前に main を
# INITIAL_MAIN_SHA まで巻き戻して単一 fixture コミットを積むことで、シナリオ
# 同士が互いを汚染しない。順序非依存で新規シナリオを自由に追加できる
#
# deletion_scenario <name> <expected-tier> <fixture-path> <fixture-content>
# fixture を base main にコミット → 削除ブランチを切って rm → 分類 → assert
deletion_scenario() {
  local name="$1" want="$2" path="$3" content="$4"
  git checkout -q main
  git reset -q --hard "$INITIAL_MAIN_SHA"
  git clean -fdq
  mkdir -p "$(dirname "$path")"
  printf '%s' "$content" > "$path"
  git add "$path" && git commit -qm "fixture: $name"
  git checkout -qb "case-$name"
  git rm -q "$path"
  git commit -qm "case: remove $name"
  assert_tier "$name" "$want"
}

# 削除ではなく変更で呼ぶ姉妹ヘルパー (誤検知しないことを確認するため)
modification_scenario() {
  local name="$1" want="$2" path="$3" initial="$4" appended="$5"
  git checkout -q main
  git reset -q --hard "$INITIAL_MAIN_SHA"
  git clean -fdq
  mkdir -p "$(dirname "$path")"
  printf '%s' "$initial" > "$path"
  git add "$path" && git commit -qm "fixture: $name"
  git checkout -qb "case-$name"
  printf '%s' "$appended" >> "$path"
  git commit -qam "case: modify $name"
  assert_tier "$name" "$want"
}

# テストファイル削除 → high (削除 ERE の各分岐)
deletion_scenario test-removal          high tests/util_test.py       $'assert 1\n'
deletion_scenario jest-removal          high __tests__/foo.js         $'export const t = 1\n'
deletion_scenario spec-removal          high spec/foo.rb              $'describe "x"\n'
deletion_scenario dot-test-removal      high src/foo.test.ts          $'test\n'
deletion_scenario dot-spec-removal      high src/foo.spec.ts          $'test\n'
deletion_scenario cases-jsonl-removal   high fixtures/example.cases.jsonl $'{}\n'

# テストファイルの変更 (削除でない) → check_deleted は発火しない
modification_scenario test-modify       medium tests/util_test.py $'assert 1\n' $'assert 2\n'

# 削除 ERE 対象パターンのファイルを「変更」しても high にならない (誤検知しない)
modification_scenario dot-test-modify   medium src/foo.test.ts   $'test\n'      $'more\n'

# テスト以外のファイル削除 → high にしない (通常 tier)
deletion_scenario non-test-removal      medium src/keep.py       $'x = 1\n'

# 大文字混在パスの削除 → grep -iE で case-insensitive にマッチして high
deletion_scenario upper-tests-dir-removal high Tests/foo.py      $'assert 1\n'
deletion_scenario upper-dot-test-removal  high src/Foo.TEST.ts   $'test\n'

# rename → check_deleted は --diff-filter=D なので発火しない (test-modify 相当)
git checkout -q main
git reset -q --hard "$INITIAL_MAIN_SHA"
git clean -fdq
mkdir -p tests
printf 'assert 1\n' > tests/util_test.py
git add tests && git commit -qm "fixture: test-rename"
git checkout -qb case-test-rename
git mv tests/util_test.py tests/renamed_test.py
git commit -qm "rename test"
assert_tier test-rename medium

# テスト削除 + docs 変更が混在 → test-removal が発火して high 維持
git checkout -q main
git reset -q --hard "$INITIAL_MAIN_SHA"
git clean -fdq
mkdir -p tests docs
printf 'assert 1\n' > tests/util_test.py
printf 'old docs\n' > docs/guide.md
git add tests docs && git commit -qm "fixture: mixed"
git checkout -qb case-test-removal-with-docs
git rm -q tests/util_test.py
printf 'new docs\n' > docs/guide.md
git add docs && git commit -qm "remove test + docs update"
assert_tier test-removal-with-docs high

echo "classify-risk tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
