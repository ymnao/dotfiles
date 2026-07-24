#!/usr/bin/env bash
set -euo pipefail

# scripts/lint-locale-pin.sh の検出ロジックを fixture で回帰テスト。
# fixture を scratch dir に generate し、そこを LINTER_ROOT にして linter を
# 走らせる (linter は repo_root を dirname/../ で解決するため、fixture 用の
# 疑似 repo root を作る)。stderr 出力を line 単位で assert する。

# 検証したい不変条件はバイト列同一性 (linter 出力は "file:line: reason" 形式)。
# 日本語ロケール環境で grep -F の照合が strcoll 依存にならないよう固定。
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

# 疑似 repo root: scripts/ に linter の copy を置き、tests/ 配下に fixture 群を置く。
# linter 本体は自分自身の絶対パスで self を除外するため、copy を作らず本物を
# 疑似 root にリンクするのは危険 (実 tests/ 配下も走査されてしまう)。
# コピーではなく env override 方式にする: 独立 root で linter を実行。
FAKE_ROOT="$WORKDIR/fake-root"
mkdir -p "$FAKE_ROOT/scripts" "$FAKE_ROOT/tests/pos" "$FAKE_ROOT/tests/neg"
cp "$LINTER" "$FAKE_ROOT/scripts/lint-locale-pin.sh"
chmod +x "$FAKE_ROOT/scripts/lint-locale-pin.sh"

write_fixture() {
    local path="$1"
    shift
    printf '%s\n' "$@" >"$path"
}

# positive fixtures: linter が warning を出すべきケース
write_fixture "$FAKE_ROOT/tests/pos/awk-equals.sh" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'echo foo | awk "\$1 == \"x\" {print}"'

# multibyte in grep 引数 (実運用: session-compact:60 相当)
write_fixture "$FAKE_ROOT/tests/pos/multibyte-grep.sh" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'echo foo | grep -q "未コミット"'

write_fixture "$FAKE_ROOT/tests/pos/sort.sh" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "b\na\n" | sort'

# negative fixtures: linter が warning を出してはいけないケース
write_fixture "$FAKE_ROOT/tests/neg/full-pin.sh" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    '# ファイル全体 pin' \
    'export LC_ALL=C' \
    'printf "b\na\n" | sort' \
    'echo foo | awk "\$1 == \"x\" {print}"'

write_fixture "$FAKE_ROOT/tests/neg/line-pin.sh" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'LC_ALL=C printf "b\na\n" | sort'

# コメント行内の日本語 + 引用符 == は warning 対象外
write_fixture "$FAKE_ROOT/tests/neg/comment-only.sh" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    '# 例: awk "$1 == \"x\"" と書く場面はロケール依存 (このコメント自体は無視)' \
    '# 日本語 grep 「対象文字列」 も想定 (コメントなのでスキップ)' \
    'echo ok'

# linter 実行 (stderr を捕捉、stdout は空のはず)
STDERR_LOG="$WORKDIR/stderr.log"
STDOUT_LOG="$WORKDIR/stdout.log"
(
    cd "$FAKE_ROOT" && bash "$FAKE_ROOT/scripts/lint-locale-pin.sh"
) >"$STDOUT_LOG" 2>"$STDERR_LOG"
rc=$?

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

# negative: warning を出さない
assert_absent "full-pin-skipped" "tests/neg/full-pin.sh"
assert_absent "line-pin-skipped" "tests/neg/line-pin.sh"
assert_absent "comment-only-skipped" "tests/neg/comment-only.sh"

# 自分自身 (fake-root/scripts/lint-locale-pin.sh) は除外される
assert_absent "self-excluded" "scripts/lint-locale-pin.sh"

echo ""
echo "lint-locale-pin tests: $pass pass, $fail fail"
[ "$fail" -eq 0 ]
