#!/usr/bin/env bash
set -euo pipefail

# /issue が使うブランチ名バリデータの exit code を pin する。
# (/next は検証ではなく「git が書いたファイルを shell が読む」機械的な
#  受け渡しなので、バリデータを使わない)
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
# 許容集合は allowlist なので、「広げすぎ」の mutation (char class にメタ文字を
# 足す形) を捕まえるにはメタ文字ごとの reject を pin する必要がある。
# 上の 7 件だけだと glob / tilde 展開を足す変更が緑のまま通る。
run_case 'glob star'             1 'a*b
'
run_case 'glob question'         1 'a?b
'
run_case 'bracket'               1 'a[b]c
'
run_case 'tilde'                 1 '~a
'
run_case 'paren'                 1 'a(b)c
'
run_case 'brace'                 1 'a{b}c
'
run_case 'dollar'                1 'a$b
'
run_case 'backslash'             1 'a\b
'
run_case 'single quote'          1 "a'b
"
run_case 'double quote'          1 'a"b
'
run_case 'newline escape'        1 'a
b
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

# --- NUL バイト: awk 単体では見えない範囲を非表示文字ゲートで塞ぐ ---
# NUL の扱いは awk 実装ごとに割れる: macOS awk (20200816) は NUL でレコードを
# 切るため `fix/a\0zzz;x` は `fix/a` だけが照合されて exit 0、ubuntu の awk は
# exit 1 (どちらも 2026-09-02 実測。後者は CI run 33639136424 で、当初この
# テストが awk 側の挙動を pin していて 3 ロケールとも落ちた)。
# `$(cat …)` は NUL を落として `fix/azzz;x` を git に渡すので、awk が通す実装では
# 「検証した文字列」と「使う文字列」がずれる = vacuous pass になる。
# **awk の挙動は pin しない** — 実装差はここで守りたい不変条件ではないし、
# プロキシを pin すると上流が変わった瞬間に無関係な赤が出る。守りたいのは
# 「SKILL.md step 7 の非表示文字ゲートが NUL を落とし、正当な名前は通す」ことだけ。
nul_file="$WORKDIR/nul.txt"
printf 'fix/a\0zzz;x\n' > "$nul_file"
nul_ctrl=$(LC_ALL=C tr -d '[:print:]\n' < "$nul_file" | LC_ALL=C wc -c | tr -d '[:space:]')
check 'NUL: 非表示文字ゲートが検出する' 1 "$nul_ctrl"
ok_ctrl=$(printf 'fix/safe-name\n' | LC_ALL=C tr -d '[:print:]\n' | LC_ALL=C wc -c | tr -d '[:space:]')
check '正当な名前は非表示文字ゲートを通る' 0 "$ok_ctrl"

# ゲートのコマンドが SKILL.md に書かれているものと同じであること。
CTRL_GATE="LC_ALL=C tr -d '[:print:]\\n' < \"\$TMPDIR/branch-name.txt\" | LC_ALL=C wc -c"

# --- SKILL.md との同一性 ---
# 現在バリデータを持つのは /issue だけ (codex 側は symlink で同じ実体)。
SKILL='claude/skills/issue/SKILL.md'
if grep -qF "$VALIDATOR" "$REPO_ROOT/$SKILL"; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL: $SKILL にこのテストと同一のバリデータ式が見つからない" >&2
  echo "      期待する式: $VALIDATOR" >&2
fi

if grep -qF "$CTRL_GATE" "$REPO_ROOT/$SKILL"; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL: $SKILL に非表示文字ゲートのコマンドが見つからない" >&2
  echo "      期待するコマンド: $CTRL_GATE" >&2
fi

echo "branch-name-validator tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
