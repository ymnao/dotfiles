#!/usr/bin/env bash
set -uo pipefail

# fish/config/pnpm.fish の function 動作テスト。
# npm / npx が exit 1 を返し、stderr に pnpm 誘導メッセージを出すことを確認する。
#
# 依存: fish (未インストールなら skip)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
TARGET="$REPO_ROOT/fish/config/pnpm.fish"

if ! command -v fish >/dev/null 2>&1; then
  echo "SKIP fish-pnpm tests: fish 未インストール"
  exit 0
fi

if [ ! -f "$TARGET" ]; then
  echo "ERROR: $TARGET が見つからない" >&2
  exit 1
fi

pass=0
fail=0

run_case() {
  local name="$1" cmd="$2" expect_pattern="$3"
  local combined status
  combined=$(fish --no-config -c "source '$TARGET'; $cmd" 2>&1 >/dev/null)
  status=$?
  if [ "$status" -ne 1 ]; then
    echo "FAIL $name: exit=$status (expected 1)"
    echo "$combined" >&2
    fail=$((fail+1))
    return
  fi
  if ! printf '%s\n' "$combined" | grep -q -- "$expect_pattern"; then
    echo "FAIL $name: stderr に \"$expect_pattern\" が見つからない"
    echo "$combined" >&2
    fail=$((fail+1))
    return
  fi
  pass=$((pass+1))
}

run_case "npm-bare"           "npm"                  "pnpm を使ってください"
run_case "npm-with-args"      "npm install lodash"   "pnpm install"
run_case "npx-bare"           "npx"                  "pnpm dlx"
run_case "npx-with-args"      "npx cowsay hi"        "pnpm dlx"

# PNPM_HOME / PATH 環境設定のテスト (exit 0 系なので run_case は使えない)
run_env_case() {
  local name="$1" cmd="$2" expect_pattern="$3"
  local combined status
  combined=$(fish --no-config -c "source '$TARGET'; $cmd" 2>&1)
  status=$?
  if [ "$status" -ne 0 ]; then
    echo "FAIL $name: exit=$status (expected 0)"
    echo "$combined" >&2
    fail=$((fail+1))
    return
  fi
  if ! printf '%s\n' "$combined" | grep -q -- "$expect_pattern"; then
    echo "FAIL $name: 出力に \"$expect_pattern\" が見つからない"
    echo "$combined" >&2
    fail=$((fail+1))
    return
  fi
  pass=$((pass+1))
}

run_env_case "pnpm-home-set"       'echo $PNPM_HOME'                                                    "/.local/share/pnpm"
# fish_add_path -g は $fish_user_paths を更新する。--no-config 環境では
# $PATH への再計算が発火しないため、$fish_user_paths を直接検証する
run_env_case "pnpm-bin-registered" 'contains $PNPM_HOME/bin $fish_user_paths; and echo REGISTERED'      "REGISTERED"
# fish_add_path は idempotent、二重 source しても fish_user_paths に重複しない
run_env_case "pnpm-bin-idempotent" 'source "'"$TARGET"'"; count (string match -a -- $PNPM_HOME/bin $fish_user_paths)' "^1\$"

echo "fish-pnpm tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
