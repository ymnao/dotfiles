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

# 各ケースで fake repo root を用意して brewfile-drift.sh を実行する。
# 実 script は `cd "$SCRIPT_DIR/.."` で自分の親を repo root にするので、
# fake root に scripts/ サブディレクトリを掘って brewfile-drift.sh と
# lib/log.sh を symlink し、Brewfile と mock brew (PATH 経由) を配置する。
run_case() {
  local name="$1" brewfile="$2" brew_stub="$3" want_rc="$4" want_stdout_re="$5" want_stderr_re="$6"
  local root
  root="$(mktemp -d "$WORKDIR/case.XXXXXX")"
  mkdir -p "$root/scripts/lib" "$root/bin"
  ln -s "$REPO_ROOT/scripts/brewfile-drift.sh" "$root/scripts/brewfile-drift.sh"
  ln -s "$REPO_ROOT/scripts/lib/log.sh" "$root/scripts/lib/log.sh"
  printf '%s\n' "$brewfile" > "$root/Brewfile"
  printf '%s\n' "$brew_stub" > "$root/bin/brew"
  chmod +x "$root/bin/brew"

  local out err rc=0
  out="$root/out"
  err="$root/err"
  # PATH は mock brew を先頭にしつつ、mktemp / awk / sed 等の system utility も残す
  PATH="$root/bin:$PATH" bash "$root/scripts/brewfile-drift.sh" >"$out" 2>"$err" || rc=$?

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
'#!/usr/bin/env bash
case "$*" in
  "leaves")     printf "ripgrep\njq\n" ;;
  "list --cask") printf "wezterm\n" ;;
  *) echo "unexpected brew args: $*" >&2; exit 99 ;;
esac' \
  0 "no drift" ""

# case 2: formula drift 検出
run_case formula-drift \
'brew "ripgrep"' \
'#!/usr/bin/env bash
case "$*" in
  "leaves")     printf "ripgrep\nfd\n" ;;
  "list --cask") : ;;
  *) exit 99 ;;
esac' \
  1 "formula: installed but not in Brewfile" ""

# case 3: cask drift 検出
run_case cask-drift \
'cask "wezterm"' \
'#!/usr/bin/env bash
case "$*" in
  "leaves")     : ;;
  "list --cask") printf "wezterm\nkarabiner-elements\n" ;;
  *) exit 99 ;;
esac' \
  1 "cask: installed but not in Brewfile" ""

# case 4: brew CLI 失敗 (leaves が exit 3) → drift なし表示ではなく失敗として扱う
run_case brew-cli-fails \
'brew "ripgrep"' \
'#!/usr/bin/env bash
case "$*" in
  "leaves")     echo "brew: catastrophic failure" >&2; exit 3 ;;
  "list --cask") : ;;
  *) exit 99 ;;
esac' \
  1 "listing installed formula failed" "catastrophic failure"

# case 5: Brewfile が読めない (permission 0) → 明示エラー
# root では chmod 000 でも読めるので skip
if [ "$(id -u)" -ne 0 ]; then
  root="$(mktemp -d "$WORKDIR/case.XXXXXX")"
  mkdir -p "$root/scripts/lib" "$root/bin"
  ln -s "$REPO_ROOT/scripts/brewfile-drift.sh" "$root/scripts/brewfile-drift.sh"
  ln -s "$REPO_ROOT/scripts/lib/log.sh" "$root/scripts/lib/log.sh"
  : > "$root/Brewfile"
  chmod 000 "$root/Brewfile"
  cat > "$root/bin/brew" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "leaves")     printf "ripgrep\n" ;;
  "list --cask") : ;;
  *) exit 99 ;;
esac
STUB
  chmod +x "$root/bin/brew"
  rc=0
  PATH="$root/bin:$PATH" bash "$root/scripts/brewfile-drift.sh" >"$root/out" 2>"$root/err" || rc=$?
  chmod 644 "$root/Brewfile"
  if [ "$rc" -eq 1 ] && grep -qE "Brewfile not readable" "$root/err"; then
    pass=$((pass + 1))
  else
    echo "FAIL brewfile-unreadable: rc=$rc stderr:"; sed 's/^/  /' "$root/err"
    fail=$((fail + 1))
  fi
fi

# case 6: tap 付き記述 (a/b/c) の正規化
# Brewfile: brew "laishulu/homebrew/macism"   installed: laishulu/homebrew/macism
# normalize() で末尾 "macism" 同士 → drift なし
run_case tap-normalized \
'brew "laishulu/homebrew/macism"' \
'#!/usr/bin/env bash
case "$*" in
  "leaves")     printf "laishulu/homebrew/macism\n" ;;
  "list --cask") : ;;
  *) exit 99 ;;
esac' \
  0 "no drift" ""

# case 7: brew leaves が空 (grep no-match でも drift 判定を壊さない)
run_case empty-leaves \
'brew "ripgrep"' \
'#!/usr/bin/env bash
case "$*" in
  "leaves")     : ;;
  "list --cask") : ;;
  *) exit 99 ;;
esac' \
  0 "no drift" ""

echo "brewfile-drift tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
