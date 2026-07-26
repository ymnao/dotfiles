#!/usr/bin/env bash
# fish/config/rbenv.fish・pyenv.fish の回帰テスト。
#
# 検証項目:
#   1. ツールが PATH に無い環境で source しても
#      - exit 0 で通る
#      - shell function が定義されない (`type -q` ガードが効いている)
#      - **出力が完全に無い**
#      3 つ目が本体。ガードを外しても exit は 0 のままで function も定義され
#      ないため、出力の有無を見ないとガードの欠落を検出できない (mutation
#      check で確認済み)。実際に観測される害は fish 起動ごとに
#      `fish: Unknown command: pyenv` が stderr に出ること。
#   2. ホストにツールが実在する場合、init 経由で shell function が
#      定義されること (未実在ならこのケースだけ skip)
#
# 依存: fish (未インストールなら全体を skip)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"

if ! command -v fish >/dev/null 2>&1; then
  echo "SKIP fish-version-managers tests: fish 未インストール"
  exit 0
fi

pass=0
fail=0

# expect_silent=1 のとき stdout/stderr が完全に空であることも要求する
run_case() {
  local name="$1" expect_exit="$2" expect_silent="$3" snippet="$4"
  local combined status
  combined=$(fish --no-config -c "$snippet" 2>&1)
  status=$?
  if [ "$status" -ne "$expect_exit" ]; then
    echo "FAIL $name: exit=$status (expected $expect_exit)"
    printf '%s\n' "$combined" >&2
    fail=$((fail + 1))
    return
  fi
  if [ "$expect_silent" -eq 1 ] && [ -n "$combined" ]; then
    echo "FAIL $name: 出力があってはならないのに出力された"
    printf '%s\n' "$combined" >&2
    fail=$((fail + 1))
    return
  fi
  pass=$((pass + 1))
}

for tool in rbenv pyenv; do
  target="$REPO_ROOT/fish/config/$tool.fish"
  if [ ! -f "$target" ]; then
    echo "ERROR: $target が見つからない" >&2
    exit 1
  fi

  # 1. 未インストール相当: PATH を最小に絞ると `type -q` が偽になる。
  #    exit 0 / function 未定義 / 無出力 の 3 点を同時に検証する。
  #    (function が定義されてしまったら `functions -q` が真になり exit 1 で FAIL)
  run_case "$tool: PATH 最小化時に無言で通りガードが効く" 0 1 \
    "set -gx PATH /usr/bin /bin; source '$target'; if functions -q $tool; exit 1; end; exit 0"

  # 2. ホストに実在する場合のみ: init 経由で shell function が定義される
  if command -v "$tool" >/dev/null 2>&1; then
    run_case "$tool: インストール済み環境で shell function が定義される" 0 0 \
      "source '$target'; if functions -q $tool; exit 0; end; exit 1"
  else
    echo "SKIP $tool: ホストに未インストールのため定義テストを skip"
  fi
done

echo "fish-version-managers: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
