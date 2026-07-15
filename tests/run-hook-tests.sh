#!/usr/bin/env bash
set -euo pipefail

# Hook 回帰テストランナー。
# 使い方: run-hook-tests.sh [cases.jsonl ...]
#   引数なし: このスクリプトと同階層の hooks/*.cases.jsonl を全実行
#
# ケース形式 (JSONL, 1 行 1 ケース。# 始まりの行と空行はスキップ):
#   {"name":"...","expect":"allow|block","command":"...","reason":"..."}     # Bash 系 (tool_input.command)
#   {"name":"...","expect":"allow|block","tool_input":{...},"reason":"..."}  # Edit/Write/apply_patch 系
#   両方指定された場合は tool_input 側を優先する。
#
# 判定:
#   - expect=allow → hook の exit code 0 を期待
#   - expect=block → hook の exit code 2 を期待
#   - claude/hooks/ と codex/hooks/ の両方に同名 hook がある場合は両方に流し、
#     exit code が一致することも検証する (ドリフト検出)
#
# 実行 cwd: mktemp -d した一時ディレクトリ (hook は pwd -P を参照するため、
# テスト結果がリポジトリ cwd に依存しないようにする)。
#
# 依存: bash 3.2+ / jq / git (リポジトリルート解決のみ)
#
# 環境変数 HOOK_DIR: 指定すると claude/codex の両系統ではなく、そのディレクトリの
# hook 単体に対してテストする (例: symlink 切り替え前の agents/hooks/ の検証用)。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# REPO_ROOT は claude/codex 両系統モードでのみ必要。HOOK_DIR モードが
# git 不在・リポジトリ外でも動くよう、git 依存はこの分岐に閉じ込める。
REPO_ROOT=""
if [ -z "${HOOK_DIR:-}" ]; then
  REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 1
fi

# ケースファイル名 → hook スクリプト名の対応。
# verify-ci は早期 exit 経路のみをテストするため名前が異なる。
hook_file_for() {
  case "$1" in
    verify-ci-early-exit) printf '%s' "verify-ci-before-pr.sh" ;;
    *) printf '%s' "$1.sh" ;;
  esac
}

# 一時 cwd (hook の pwd -P 参照対策)
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/hook-tests.XXXXXX")"
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT

# 対象ケースファイルの決定 (引数なしなら glob。SC2045 回避のため ls は使わない)
if [ "$#" -eq 0 ]; then
  set -- "$SCRIPT_DIR"/hooks/*.cases.jsonl
  if [ ! -f "$1" ]; then
    echo "ERROR: no case files found under $SCRIPT_DIR/hooks/" >&2
    exit 1
  fi
fi

pass=0
fail=0

run_hook() {
  # $1=hook path, $2=input json。exit code を echo する (0/2 以外もそのまま)
  local rc=0
  printf '%s' "$2" | (cd "$WORKDIR" && bash "$1" >/dev/null 2>&1) || rc=$?
  printf '%s' "$rc"
}

for cf in "$@"; do
  base=$(basename "$cf" .cases.jsonl)
  hook_name=$(hook_file_for "$base")
  if [ -n "${HOOK_DIR:-}" ]; then
    claude_hook="$HOOK_DIR/$hook_name"
    codex_hook=""
  else
    claude_hook="$REPO_ROOT/claude/hooks/$hook_name"
    codex_hook="$REPO_ROOT/codex/hooks/$hook_name"
  fi
  [ -f "$claude_hook" ] || claude_hook=""
  [ -f "$codex_hook" ] || codex_hook=""
  if [ -z "$claude_hook" ] && [ -z "$codex_hook" ]; then
    echo "ERROR: hook not found for $cf ($hook_name)" >&2
    exit 1
  fi

  echo "==> $base"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    name=$(printf '%s' "$line" | jq -r '.name')
    expect=$(printf '%s' "$line" | jq -r '.expect')
    case "$expect" in
      allow) want=0 ;;
      block) want=2 ;;
      *) echo "FAIL $name: invalid expect '$expect'"; fail=$((fail + 1)); continue ;;
    esac
    # ケース形式: `tool_input` を JSON オブジェクトで直接指定 (Edit/Write/apply_patch 系)。
    # 後方互換で `command` 文字列も受け付け、tool_input.command に組み立てる (Bash 系)。
    # 両方指定された場合は tool_input 側を優先する。
    input=$(printf '%s' "$line" | jq -c '{tool_input: (.tool_input // {command: .command})}')

    got_claude=""
    got_codex=""
    [ -n "$claude_hook" ] && got_claude=$(run_hook "$claude_hook" "$input")
    [ -n "$codex_hook" ] && got_codex=$(run_hook "$codex_hook" "$input")

    ok=1
    [ -n "$got_claude" ] && [ "$got_claude" != "$want" ] && ok=0
    [ -n "$got_codex" ] && [ "$got_codex" != "$want" ] && ok=0
    if [ -n "$got_claude" ] && [ -n "$got_codex" ] && [ "$got_claude" != "$got_codex" ]; then
      ok=0  # 両系統ドリフト
    fi

    if [ "$ok" = 1 ]; then
      pass=$((pass + 1))
    else
      echo "FAIL $name: expected=$want claude=${got_claude:--} codex=${got_codex:--} input: $input"
      fail=$((fail + 1))
    fi
  done < "$cf"
done

echo "----"
echo "hook tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
