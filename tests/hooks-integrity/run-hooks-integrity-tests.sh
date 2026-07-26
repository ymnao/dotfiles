#!/usr/bin/env bash
#
# agents/hooks/hooks-integrity-warn.sh の回帰テスト (issue #207)。
#
# 検証内容:
#   1. 検知ロジック — 監視対象パスの未コミット改変だけを警告し、対象外の
#      変更や clean な repo では何も出さない。常に exit 0 (warn-only)
#   2. 配線 — claude/hooks/ からの symlink・settings.json の SessionStart
#      エントリ・tests/run-gate.sh からの呼び出しが揃っている
#
# 一時 git repo を $TMPDIR に作って検知ロジックを回す。検査対象 repo は
# HOOKS_INTEGRITY_REPO で差し替える (hook 側が用意している上書き口)。

set -uo pipefail

# 期待文字列 (日本語) をバイト一致で比較するためロケールを固定する。
# ambient ロケール依存で grep の一致判定が揺れるのを防ぐ (issue #181 / #192)。
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
HOOK="$REPO_ROOT/agents/hooks/hooks-integrity-warn.sh"

pass=0
fail=0

check() {
  # $1=condition (0=OK), $2=description
  if [ "$1" = "0" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL: $2"
    fail=$((fail + 1))
  fi
}

# `[ -z "$out" ]` の直後に `check "$?"` と書くと SC2319 になるため、
# 空判定は専用ヘルパーに寄せる。
check_empty() {
  # $1=検査する出力, $2=description
  if [ -z "$1" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL: $2 (got: $1)"
    fail=$((fail + 1))
  fi
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/hooks-integrity-test.XXXXXX") || exit 1
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

FIXTURE="$WORK/repo"
mkdir -p "$FIXTURE/agents/hooks" "$FIXTURE/claude/hooks" "$FIXTURE/codex/hooks"
printf 'echo base\n' > "$FIXTURE/agents/hooks/sample.sh"
printf '{}\n' > "$FIXTURE/codex/hooks.json"
printf '{}\n' > "$FIXTURE/claude/settings.json"
printf 'readme\n' > "$FIXTURE/README.md"

git -C "$FIXTURE" init -q
git -C "$FIXTURE" add -A
git -C "$FIXTURE" \
  -c user.email=test@example.com \
  -c user.name=test \
  commit -qm "init"

run_hook() {
  HOOKS_INTEGRITY_REPO="$1" bash "$HOOK" 2>&1
}

# --- 1. clean な repo では何も出さない ---
out=$(run_hook "$FIXTURE"); rc=$?
check "$rc" "clean repo で exit 0 を返すこと (got $rc)"
check_empty "$out" "clean repo で出力が空であること"

# --- 2. 監視対象外の変更は無視する ---
printf 'changed\n' >> "$FIXTURE/README.md"
out=$(run_hook "$FIXTURE"); rc=$?
check "$rc" "対象外変更のみでも exit 0 (got $rc)"
check_empty "$out" "対象外変更 (README.md) を警告しないこと"

# --- 3. 正本 hook の改変を検知する ---
printf 'echo tampered\n' >> "$FIXTURE/agents/hooks/sample.sh"
out=$(run_hook "$FIXTURE"); rc=$?
check "$rc" "改変検知時も exit 0 を返すこと (warn-only、got $rc)"
printf '%s' "$out" | grep -q '\[hooks-integrity\]'
check "$?" "改変時に警告ラベルを出すこと"
printf '%s' "$out" | grep -q 'agents/hooks/sample.sh'
check "$?" "改変されたパスを出力に含めること"
git -C "$FIXTURE" checkout -q -- agents/hooks/sample.sh

# --- 4. codex/hooks 配下の未追跡ファイルを検知する (-uall) ---
printf 'echo new\n' > "$FIXTURE/codex/hooks/injected.sh"
out=$(run_hook "$FIXTURE")
printf '%s' "$out" | grep -q 'codex/hooks/injected.sh'
check "$?" "codex/hooks 配下の未追跡ファイルを検知すること"
rm -f "$FIXTURE/codex/hooks/injected.sh"

# --- 5. hook 定義ファイル (hooks.json / settings.json) の改変を検知する ---
printf '{"x":1}\n' > "$FIXTURE/codex/hooks.json"
out=$(run_hook "$FIXTURE")
printf '%s' "$out" | grep -q 'codex/hooks.json'
check "$?" "codex/hooks.json の改変を検知すること"
git -C "$FIXTURE" checkout -q -- codex/hooks.json

printf '{"x":1}\n' > "$FIXTURE/claude/settings.json"
out=$(run_hook "$FIXTURE")
printf '%s' "$out" | grep -q 'claude/settings.json'
check "$?" "claude/settings.json の改変を検知すること"
git -C "$FIXTURE" checkout -q -- claude/settings.json

# --- 6. git repo でないディレクトリでは fail-open ---
mkdir -p "$WORK/notrepo"
out=$(run_hook "$WORK/notrepo"); rc=$?
check "$rc" "git repo 外で exit 0 (fail-open、got $rc)"
check_empty "$out" "git repo 外で出力が空であること"

# --- 7. 存在しないパスでも fail-open ---
out=$(run_hook "$WORK/missing"); rc=$?
check "$rc" "存在しない repo パスで exit 0 (got $rc)"
check_empty "$out" "存在しない repo パスで出力が空であること"

# --- 8. 配線: claude/hooks/ からの symlink が正本に解決される ---
LINK="$REPO_ROOT/claude/hooks/hooks-integrity-warn.sh"
[ -L "$LINK" ]
check "$?" "claude/hooks/hooks-integrity-warn.sh が symlink であること"
if [ -L "$LINK" ]; then
  resolved=$(cd "$(dirname "$LINK")" && cd "$(dirname "$(readlink "$LINK")")" && pwd -P)/$(basename "$(readlink "$LINK")")
  [ "$resolved" = "$HOOK" ]
  check "$?" "symlink が agents/hooks/hooks-integrity-warn.sh に解決されること (got $resolved)"
fi

# --- 9. 配線: settings.json の SessionStart に startup|resume エントリがある ---
if command -v jq >/dev/null 2>&1; then
  found=$(jq -r '
    .hooks.SessionStart[]
    | select(.matcher | test("startup"))
    | .hooks[].command
  ' "$REPO_ROOT/claude/settings.json" 2>/dev/null | grep -c 'hooks-integrity-warn.sh' || true)
  [ "$found" -ge 1 ]
  check "$?" "settings.json の SessionStart(startup) が hooks-integrity-warn.sh を呼ぶこと"
fi

# --- 10. 配線: run-gate.sh から呼ばれている ---
grep -q 'hooks-integrity-warn.sh' "$REPO_ROOT/tests/run-gate.sh"
check "$?" "tests/run-gate.sh が hooks-integrity-warn.sh を呼ぶこと"

echo "hooks-integrity: ${pass} passed, ${fail} failed"
[ "$fail" = 0 ] || exit 1
