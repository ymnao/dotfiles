#!/usr/bin/env bash
set -euo pipefail

# scripts/lint-locale-pin.sh の検出ロジックを fixture で回帰テスト。
# LINT_LOCALE_PIN_ROOT を scratch dir に向け、そこに fixture 群を配置して
# 実 linter を直接起動する。stderr 出力を line 単位で assert する。

# linter 出力は "file:line: reason" 形式。日本語ロケール環境で grep -F の
# 照合が strcoll 依存にならないよう固定。
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
LINTER="$REPO_ROOT/scripts/lint-locale-pin.sh"

if [ ! -x "$LINTER" ]; then
    echo "ERROR: linter not executable: $LINTER" >&2
    exit 1
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/lint-locale-pin.XXXXXX")"
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT

FAKE_ROOT="$WORKDIR/fake-root"
mkdir -p "$FAKE_ROOT/scripts" "$FAKE_ROOT/tests/pos" "$FAKE_ROOT/tests/neg"

write_fixture() {
    local path="$1"
    shift
    {
        printf '#!/usr/bin/env bash\nset -euo pipefail\n'
        printf '%s\n' "$@"
    } >"$path"
}

# positive: linter が warning を出すべきケース
write_fixture "$FAKE_ROOT/tests/pos/awk-equals.sh" \
    'echo foo | awk "\$1 == \"x\" {print}"'
write_fixture "$FAKE_ROOT/tests/pos/multibyte-grep.sh" \
    'echo foo | grep -q "未コミット"'
write_fixture "$FAKE_ROOT/tests/pos/sort.sh" \
    'printf "b\na\n" | sort'

# negative: linter が warning を出してはいけないケース
write_fixture "$FAKE_ROOT/tests/neg/full-pin.sh" \
    '# ファイル全体 pin' \
    'export LC_ALL=C' \
    'printf "b\na\n" | sort' \
    'echo foo | awk "\$1 == \"x\" {print}"'
# NOTE: 行スコープ pin は `LC_ALL=... <対象コマンド>` のように対象コマンド
# 自身に prefix された場合のみ実際にロケール固定として機能する。パイプライン
# 先頭コマンドへの代入 (`LC_ALL=C printf ... | sort`) は sort に伝播しないが、
# 現状の linter はそれを検出せず line-skip する (issue #192 の warning-only
# 設計方針の範囲)。fixture は「対象コマンド直前 pin」の代表例で書く。
write_fixture "$FAKE_ROOT/tests/neg/line-pin.sh" \
    'LC_ALL=C sort /etc/hostname'
write_fixture "$FAKE_ROOT/tests/neg/comment-only.sh" \
    '# 例: awk "$1 == \"x\"" と書く場面はロケール依存 (このコメント自体は無視)' \
    '# 日本語 grep 「対象文字列」 も想定 (コメントなのでスキップ)' \
    'echo ok'

# altitude A1 regression: pin より前の violation は検出される
write_fixture "$FAKE_ROOT/tests/pos/pin-after-violation.sh" \
    'printf "b\na\n" | sort' \
    'export LC_ALL=C' \
    'printf "b\na\n" | sort'

# multibyte × 比較 context の awk / [[ / =~ 各分岐 (grep 以外) 検出
write_fixture "$FAKE_ROOT/tests/pos/multibyte-awk.sh" \
    'echo foo | awk "/日本語/ {print}"'
write_fixture "$FAKE_ROOT/tests/pos/multibyte-bracket.sh" \
    'x=y' \
    '[[ "$x" = "未定" ]] && echo yes'
write_fixture "$FAKE_ROOT/tests/pos/multibyte-regex.sh" \
    'x=y' \
    '[[ "$x" =~ 未定 ]] && echo yes'

# sort 単語境界: mysort / sort_key / sort-file は誤検出しない、
# 括弧・セミコロン境界の sort は検出する
write_fixture "$FAKE_ROOT/tests/neg/sort-wordish.sh" \
    'mysort=1' \
    'sort_key=1' \
    'echo sort-file'
write_fixture "$FAKE_ROOT/tests/pos/sort-punct.sh" \
    '(sort /etc/hostname)'

# self exclusion: fake-root 内の scripts/lint-locale-pin.sh は sort を含んでも
# skip される (linter 自身のパターン記述の自己ヒット防止)
write_fixture "$FAKE_ROOT/scripts/lint-locale-pin.sh" \
    'printf "b\na\n" | sort'

# 実 linter を fake-root に向けて起動
STDERR_LOG="$WORKDIR/stderr.log"
STDOUT_LOG="$WORKDIR/stdout.log"
# set -e 下では linter 非 0 終了時に次行の rc=$? に到達しないため、
# コマンド自体を || で受けて rc を捕捉する。
rc=0
LINT_LOCALE_PIN_ROOT="$FAKE_ROOT" bash "$LINTER" >"$STDOUT_LOG" 2>"$STDERR_LOG" || rc=$?

pass=0
fail=0

assert_line() {
    local desc="$1" pattern="$2"
    if grep -Fq "$pattern" "$STDERR_LOG"; then
        pass=$((pass + 1))
    else
        echo "FAIL $desc: 期待する warning が出ていない: $pattern" >&2
        fail=$((fail + 1))
    fi
}

assert_absent() {
    local desc="$1" pattern="$2"
    if grep -Fq "$pattern" "$STDERR_LOG"; then
        echo "FAIL $desc: 想定外の warning が出ている: $pattern" >&2
        fail=$((fail + 1))
    else
        pass=$((pass + 1))
    fi
}

# exit code は常に 0 (warning-only)
if [ "$rc" -eq 0 ]; then
    pass=$((pass + 1))
else
    echo "FAIL exit-code: warning-only なので exit 0 を期待したが $rc" >&2
    fail=$((fail + 1))
fi

# stdout は空
if [ ! -s "$STDOUT_LOG" ]; then
    pass=$((pass + 1))
else
    echo "FAIL stdout: warning は stderr に出すべきだが stdout に出力あり" >&2
    fail=$((fail + 1))
fi

# positive: それぞれ期待する reason で検出される
assert_line "awk-equals-detected" "tests/pos/awk-equals.sh:3: awk-equals"
assert_line "multibyte-detected" "tests/pos/multibyte-grep.sh:3: multibyte"
assert_line "sort-detected" "tests/pos/sort.sh:3: sort"
assert_line "multibyte-awk" "tests/pos/multibyte-awk.sh:3: multibyte"
assert_line "multibyte-bracket" "tests/pos/multibyte-bracket.sh:4: multibyte"
assert_line "multibyte-regex" "tests/pos/multibyte-regex.sh:4: multibyte"
assert_line "sort-punct-detected" "tests/pos/sort-punct.sh:3: sort"
assert_absent "sort-wordish-skipped" "tests/neg/sort-wordish.sh"
# pin-after-violation: 1 行目 (pin 前) は検出、3 行目 (pin 後) は検出されない
assert_line "pin-after-violation-caught" "tests/pos/pin-after-violation.sh:3: sort"
assert_absent "pin-after-violation-post-skipped" "pin-after-violation.sh:5:"

# negative: warning を出さない
assert_absent "full-pin-skipped" "tests/neg/full-pin.sh"
assert_absent "line-pin-skipped" "tests/neg/line-pin.sh"
assert_absent "comment-only-skipped" "tests/neg/comment-only.sh"

# 自分自身は除外される
assert_absent "self-excluded" "scripts/lint-locale-pin.sh"

echo ""
echo "lint-locale-pin tests: $pass pass, $fail fail"
[ "$fail" -eq 0 ]
