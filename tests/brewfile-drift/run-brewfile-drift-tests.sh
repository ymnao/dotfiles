#!/usr/bin/env bash
set -euo pipefail

# scripts/brewfile-drift.sh の fixture 回帰テスト。
#
# 検証観点 (PR #133 shell-senior UNRESOLVED を回帰でカバー):
#   1. drift なし → exit 0
#   2. formula drift 検出 → exit 1 + drift 名を出力
#   3. cask drift 検出 → exit 1
#   4. brew CLI 失敗 (exit >=2) → exit 1 + stderr 表示 (pipeline 失敗の伝播)
#   5. Brewfile 不読 → exit 1
#   6. tap 付き記述 (a/b/c) が最終要素で正規化される
#   7. `brew leaves` の grep no-match は正常系 (drift なし判定を壊さない)
#   8. uv / cargo / pnpm が無ければ skip する
#   9. uv / cargo の global を Brewfile の uv / cargo 行と突き合わせる
#  10. pnpm の global は宣言先が無く、あれば scope 付きの名前のまま drift として出す
#  11. uv の listing 失敗 → exit 1 (drift なし表示にしない)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
TARGET="$REPO_ROOT/scripts/brewfile-drift.sh"

if [ ! -f "$TARGET" ]; then
  echo "ERROR: target not found: $TARGET" >&2
  exit 1
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/brewfile-drift-tests.XXXXXX")"
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT

pass=0
fail=0

# mock brew shim を組み立てる。$1: `brew leaves` の body、$2: `brew list --cask` の body。
# body は shell 文 (例: 'printf "ripgrep\n"' や ':')。
make_stub() {
  printf 'case "$*" in\n  "leaves") %s ;;\n  "list --cask") %s ;;\n  *) exit 99 ;;\nesac\n' "$1" "$2"
}

# $1: bin dir、$2: コマンド名、$3: body (shell 文)
stub() {
  printf '#!/usr/bin/env bash\n%s\n' "$3" > "$1/$2"
  chmod +x "$1/$2"
}

# host に入っている uv / cargo / pnpm を拾わないよう、PATH を system utility だけに絞ったうえで
# 3 つとも空の一覧を返すスタブを先に置く。/usr/bin に cargo を置く Linux もあり、PATH を絞るだけでは
# 実物が残るため。jq は pnpm の listing で使うので host のものを bin に置く。
prepare_bin() {
  mkdir -p "$1"
  ln -s "$(command -v jq)" "$1/jq"
  stub "$1" uv ':'
  stub "$1" cargo ':'
  stub "$1" pnpm "printf '[]\n'"
}
CASE_PATH_TAIL="/usr/bin:/bin"

# 各ケースで fake repo root を用意して brewfile-drift.sh を実行する。
# 実 script は `cd "$SCRIPT_DIR/.."` で自分の親を repo root にするので、
# fake root に scripts/ サブディレクトリを掘って brewfile-drift.sh と
# lib/log.sh を symlink し、Brewfile と mock brew (PATH 経由) を配置する。
run_case() {
  local name="$1" brewfile="$2" brew_stub="$3" want_rc="$4" want_stdout_re="$5" want_stderr_re="$6" setup="${7:-}"
  local root
  root="$(mktemp -d "$WORKDIR/case.XXXXXX")"
  mkdir -p "$root/scripts/lib"
  prepare_bin "$root/bin"
  ln -s "$REPO_ROOT/scripts/brewfile-drift.sh" "$root/scripts/brewfile-drift.sh"
  ln -s "$REPO_ROOT/scripts/lib/log.sh" "$root/scripts/lib/log.sh"
  printf '%s\n' "$brewfile" > "$root/Brewfile"
  stub "$root/bin" brew "$brew_stub"
  [ -z "$setup" ] || "$setup" "$root/bin"

  local out err rc=0
  out="$root/out"
  err="$root/err"
  PATH="$root/bin:$CASE_PATH_TAIL" "$BASH" "$root/scripts/brewfile-drift.sh" >"$out" 2>"$err" || rc=$?

  local ok=1
  if [ "$rc" -ne "$want_rc" ]; then
    echo "FAIL $name: rc want=$want_rc got=$rc"
    ok=0
  fi
  if [ -n "$want_stdout_re" ] && ! grep -qE "$want_stdout_re" "$out" "$err"; then
    echo "FAIL $name: stdout/stderr does not match /$want_stdout_re/"
    echo "  --- stdout"; sed 's/^/  /' "$out"
    echo "  --- stderr"; sed 's/^/  /' "$err"
    ok=0
  fi
  if [ -n "$want_stderr_re" ] && ! grep -qE "$want_stderr_re" "$err"; then
    echo "FAIL $name: stderr does not match /$want_stderr_re/"
    echo "  --- stderr"; sed 's/^/  /' "$err"
    ok=0
  fi
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
  fi
}

# case 1: drift なし (formula/cask 全て Brewfile に記載)
run_case no-drift \
'brew "ripgrep"
brew "jq"
cask "wezterm"' \
"$(make_stub 'printf "ripgrep\njq\n"' 'printf "wezterm\n"')" \
  0 "no drift" ""

# case 2: formula drift 検出
run_case formula-drift \
'brew "ripgrep"' \
"$(make_stub 'printf "ripgrep\nfd\n"' ':')" \
  1 "formula: installed but not in Brewfile" ""

# case 3: cask drift 検出
run_case cask-drift \
'cask "wezterm"' \
"$(make_stub ':' 'printf "wezterm\nkarabiner-elements\n"')" \
  1 "cask: installed but not in Brewfile" ""

# case 4: brew CLI 失敗 (leaves が exit 3) → drift なし表示ではなく失敗として扱う
run_case brew-cli-fails \
'brew "ripgrep"' \
"$(make_stub 'echo "brew: catastrophic failure" >&2; exit 3' ':')" \
  1 "listing installed formula failed" "catastrophic failure"

# case 5: Brewfile が読めない (permission 0) → 明示エラー
# root では chmod 000 でも読めるので skip
setup_brewfile_unreadable() { chmod 000 "$1/../Brewfile"; }
if [ "$(id -u)" -ne 0 ]; then
  run_case brewfile-unreadable \
  '' \
  "$(make_stub 'printf "ripgrep\n"' ':')" \
    1 "" "Brewfile not readable" setup_brewfile_unreadable
fi

# case 6: tap 付き記述 (a/b/c) の正規化
# Brewfile: brew "laishulu/homebrew/macism"   installed: laishulu/homebrew/macism
# normalize() で末尾 "macism" 同士 → drift なし
run_case tap-normalized \
'brew "laishulu/homebrew/macism"' \
"$(make_stub 'printf "laishulu/homebrew/macism\n"' ':')" \
  0 "no drift" ""

# case 7: brew leaves が空 (grep no-match でも drift 判定を壊さない)
run_case empty-leaves \
'brew "ripgrep"' \
"$(make_stub ':' ':')" \
  0 "no drift" ""

# case 8: uv / cargo / pnpm が無い → skip して drift なし
# system 側の PATH に実物がある host では「無い」状態を作れないので飛ばす
setup_globals_absent() { rm -f "$1/uv" "$1/cargo" "$1/pnpm"; }
if [ -z "$(PATH="$CASE_PATH_TAIL" command -v uv cargo pnpm)" ]; then
  run_case globals-absent-skip \
  'brew "ripgrep"' \
  "$(make_stub 'printf "ripgrep\n"' ':')" \
    0 'pnpm not installed' '' setup_globals_absent
fi

setup_uv_cargo_declared() {
  stub "$1" uv 'printf "claude-usage-monitor v3.1.0\n- claude-monitor\n"'
  stub "$1" cargo 'printf "bat v0.24.0:\n    bat\nfoo v0.1.0 (https://example.com/foo#abc):\n    foo\n"'
}
# case 9a: Brewfile の uv / cargo 行に揃っていれば drift なし (entrypoint 行・bin 行を名前と誤読しない)
run_case uv-cargo-declared \
'brew "ripgrep"
uv "claude-usage-monitor"
cargo "bat"
cargo "foo"' \
"$(make_stub 'printf "ripgrep\n"' ':')" \
  0 "no drift" "" setup_uv_cargo_declared

# case 9b: uv の未宣言を検出
run_case uv-drift \
'brew "ripgrep"
cargo "bat"
cargo "foo"' \
"$(make_stub 'printf "ripgrep\n"' ':')" \
  1 '^  claude-usage-monitor$' "" setup_uv_cargo_declared

# case 9c: cargo の未宣言を検出
run_case cargo-drift \
'brew "ripgrep"
uv "claude-usage-monitor"
cargo "bat"' \
"$(make_stub 'printf "ripgrep\n"' ':')" \
  1 '^  foo$' "" setup_uv_cargo_declared

setup_pnpm_exe() {
  stub "$1" pnpm 'printf "%s\n" "[{\"path\":\"/g\",\"dependencies\":{\"@pnpm/exe\":{\"version\":\"11.5.2\"}}}]"'
}
# case 10a: pnpm の global は scope 付きの名前のまま drift として出す
run_case pnpm-drift \
'brew "ripgrep"' \
"$(make_stub 'printf "ripgrep\n"' ':')" \
  1 '^  @pnpm/exe$' "" setup_pnpm_exe

setup_pnpm_empty() {
  stub "$1" pnpm 'printf "%s\n" "[{\"path\":\"/g\",\"private\":true}]"'
}
# case 10b: pnpm の global が 0 件 (dependencies キーが無い) → drift なし
run_case pnpm-empty \
'brew "ripgrep"' \
"$(make_stub 'printf "ripgrep\n"' ':')" \
  0 "no drift" "" setup_pnpm_empty

setup_uv_fails() {
  stub "$1" uv 'echo "error: Operation not permitted" >&2; exit 2'
}
# case 11: uv の listing 失敗 → drift なし表示ではなく失敗として扱う
run_case uv-list-fails \
'brew "ripgrep"' \
"$(make_stub 'printf "ripgrep\n"' ':')" \
  1 "listing installed uv failed" "Operation not permitted" setup_uv_fails

echo "brewfile-drift tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
