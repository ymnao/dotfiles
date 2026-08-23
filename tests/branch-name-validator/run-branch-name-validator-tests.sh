#!/usr/bin/env bash
set -euo pipefail

# /issue と /next が使うブランチ名バリデータの exit code を pin する。
#
# 2026-08-23 に、main rule 側で `{exit 1}` する形を出荷して false ACCEPT を
# 作った。awk の `exit` は END を実行してから終了し、END の `exit <expr>` が
# status を上書きするため、1 行の入力なら `foo$(id);x` でも exit 0 になる。
# 「安全な文字集合の外なら exit 1」という中心的な主張が反転していた。
#
# このテストは 2 つを同時に見る:
#   1. バリデータ式の exit code (敵対入力を reject し、正当な名前を accept する)
#   2. その式が SKILL.md に書かれている式と**同一**であること (drift 防止)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"

# SKILL.md に書かれているものと 1 文字も違わないこと。片方だけ直す drift を
# 防ぐため、この文字列は下の grep -F でも使う。
VALIDATOR='NR>1 || $0 !~ /^[abcdefghijklmnopqrstuvwxyz0123456789][abcdefghijklmnopqrstuvwxyz0123456789\/._#-]*$/ {bad=1} END{exit (bad || NR!=1)}'

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/branch-name-validator.XXXXXX")"
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT

pass=0
fail=0

check() {
  local label="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $label (want exit $want, got $got)" >&2
  fi
}

# 入力はファイル経由で渡す。SKILL.md の手順が「名前を shell の
# コマンド文字列に置かない」ことを要求しているので、テストも同じ経路で測る。
run_case() {
  local label="$1" want="$2" body="$3"
  local f="$WORKDIR/case.txt"
  printf '%s' "$body" > "$f"
  local got=0
  LC_ALL=C awk "$VALIDATOR" "$f" || got=$?
  check "$label" "$want" "$got"
}

# --- accept (exit 0): 正当なブランチ名 ---
run_case 'plain name'            0 'fix/safe-name
'
run_case 'issue-number suffix'   0 'feature/add-user-auth-#42
'
run_case 'dots and underscores'  0 'refactor/a.b_c-d/e
'
run_case 'single character'      0 'a
'
run_case 'no trailing newline'   0 'fix/safe-name'

# --- reject (exit 1): shell メタ文字 ---
run_case 'command substitution'  1 'foo$(id);x
'
run_case 'backticks'             1 'a`id`b
'
run_case 'semicolon'             1 'a;id
'
run_case 'ampersand'             1 'a&b
'
run_case 'pipe'                  1 'a|b
'
run_case 'space'                 1 'a b
'
run_case 'redirect'              1 'a>b
'

# --- reject (exit 1): option injection と文字集合外 ---
run_case 'leading dash'          1 '-d
'
run_case 'leading dot'           1 '.hidden
'
run_case 'uppercase'             1 'Fix/Foo
'

# --- reject (exit 1): 行数 ---
# 1 行目が safe で 2 行目が敵対的なケース。行単位の grep -q はここを
# 通してしまい、改行がコマンド区切りとして働く。
run_case 'safe line then hostile' 1 'fix/safe-name
$(id)
'
run_case 'empty file'            1 ''
run_case 'newline only'          1 '
'

# --- SKILL.md との同一性 ---
for skill in claude/skills/issue/SKILL.md; do
  if grep -qF "$VALIDATOR" "$REPO_ROOT/$skill"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $skill にこのテストと同一のバリデータ式が見つからない" >&2
    echo "      期待する式: $VALIDATOR" >&2
  fi
done

echo "branch-name-validator tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
