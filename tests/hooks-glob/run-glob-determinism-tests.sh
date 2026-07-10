#!/usr/bin/env bash
set -uo pipefail

# block-dangerous-commands.sh の「判定が cwd の中身に依存しない」ことのテスト。
# 修正前は unquoted 展開の glob により、`.codex/` が実在する cwd では
# `cat .co*` のような無害な読み取りが `.codex` に展開されてブロックされた。
# 同一コマンドを「.codex あり / なし」両方の cwd で実行し、結果が一致し
# かつ期待どおりであることを検証する。
#
# 使い方: run-glob-determinism-tests.sh
#   環境変数 HOOK_PATH で hook の場所を上書きできる
#   (デフォルト: <リポジトリルート>/claude/hooks/block-dangerous-commands.sh)
#
# 依存: bash 3.2+ / jq

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
HOOK="${HOOK_PATH:-$REPO_ROOT/claude/hooks/block-dangerous-commands.sh}"

if [ ! -f "$HOOK" ]; then
  echo "ERROR: hook not found: $HOOK (HOOK_PATH で上書き可)" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }

BASE="$(mktemp -d "${TMPDIR:-/tmp}/glob-tests.XXXXXX")"
cleanup() { [ -n "${BASE:-}" ] && rm -rf "$BASE"; }
trap cleanup EXIT

# cwd 2 種: .codex が「無い」/「ある」
PLAIN="$BASE/plain"
WITH_CODEX="$BASE/with-codex"
mkdir -p "$PLAIN" "$WITH_CODEX/.codex"
printf 'x\n' >"$WITH_CODEX/.codex/config.toml"

pass=0
fail=0

# $1=cwd, $2=command。exit code を echo
run_hook_in() {
  local json rc=0
  json=$(jq -cn --arg c "$2" '{"tool_input":{"command":$c}}')
  printf '%s' "$json" | (cd "$1" && bash "$HOOK" >/dev/null 2>&1) || rc=$?
  printf '%s' "$rc"
}

# $1=テスト名, $2=期待 exit (両 cwd 共通), $3=command
check_both() {
  local got_plain got_codex ok=1
  got_plain=$(run_hook_in "$PLAIN" "$3")
  got_codex=$(run_hook_in "$WITH_CODEX" "$3")
  [ "$got_plain" = "$2" ] || ok=0
  [ "$got_codex" = "$2" ] || ok=0
  [ "$got_plain" = "$got_codex" ] || ok=0
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $1: expected=$2 plain=$got_plain with-codex=$got_codex cmd: $3"
    fail=$((fail + 1))
  fi
}

# glob を含む無害な読み取りは cwd の中身に関わらず許可される
check_both "glob-read-cat"    0 "git status; cat .co*"
check_both "glob-read-ls"     0 "git log --oneline -3; ls .c*"
check_both "glob-read-head"   0 "head .co* 2>/dev/null"

# リテラルの .codex 書き込み・作成は cwd の中身に関わらずブロックされる
check_both "literal-mkdir"    2 "mkdir .codex"
check_both "literal-redirect" 2 "echo x > .codex/config.toml"

# リテラルの .codex 読み取りは readonly 緩和で許可される (両 cwd で一致)
check_both "literal-cat-read" 0 "cat .codex/config.toml"

echo "----"
echo "glob determinism tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
