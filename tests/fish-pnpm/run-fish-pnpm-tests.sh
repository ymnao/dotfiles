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

# fish 4.x の fish_add_path は存在しないディレクトリを黙ってスキップするため、
# ユーザー環境の ~/.local/share/pnpm/bin 有無に依存させないよう mktemp した
# WORKDIR を PNPM_HOME として注入する。pnpm.fish 側は `set -q PNPM_HOME` で
# 既設定を尊重するので、ここで export した値が pnpm.fish 内でそのまま使われる
#
# TMPDIR は連結前に末尾の `/` を落とす (issue #225)。macOS の TMPDIR は
# 末尾がスラッシュ (`getconf DARWIN_USER_TEMP_DIR` → `/var/folders/.../T/`)
# なので、そのまま連結すると WORKDIR に `//` が入る。fish 側の
# `fish_add_path` は `builtin realpath -s` で正規化した値を $fish_user_paths
# に入れる (`//` → `/`) ため、bash 側の生パスと文字列比較する
# pnpm-bin-registered / pnpm-bin-idempotent だけが落ちる。
# 「TMPDIR に末尾スラッシュが付くかどうか」でしか差が出ないので、実行環境に
# よって flaky に見えた。
# 同じ正規化が tests/fish-version-managers/ と tests/link/ にもある (原因は
# 同一、正規化する側のツールだけが違う)。共有ヘルパにしていないのは repo に
# テスト間共有ライブラリの前例が無く、各スイートを自己完結に保つ様式のため。
# 4 件目が出たら tests/lib/ への抽出を検討する。
TMP_BASE="${TMPDIR:-/tmp}"
while [ "$TMP_BASE" != "${TMP_BASE%/}" ]; do
  TMP_BASE="${TMP_BASE%/}"
done
WORKDIR="$(mktemp -d "$TMP_BASE/fish-pnpm-test.XXXXXX")" || {
  echo "ERROR: mktemp -d failed" >&2
  exit 1
}
trap 'rm -rf "$WORKDIR"' EXIT
# 末尾以外の `//` (TMPDIR=/a//b 等) はここでは潰していない。残っていると
# 上記と同じ経路で 2 ケースだけが謎に落ちるので、原因の分かる形で即死させる。
# trap の後に置くのは、ここで exit しても作った WORKDIR を残さないため。
case "$WORKDIR" in
  *//*)
    echo "ERROR: WORKDIR に // が残っている ($WORKDIR)。TMPDIR を正規化して再実行すること" >&2
    exit 1
    ;;
esac
mkdir -p "$WORKDIR/bin"
export PNPM_HOME="$WORKDIR"

pass=0
fail=0

run_case() {
  local name="$1" expect_exit="$2" cmd="$3" expect_pattern="$4"
  local combined status
  combined=$(fish --no-config -c "source '$TARGET'; $cmd" 2>&1)
  status=$?
  if [ "$status" -ne "$expect_exit" ]; then
    echo "FAIL $name: exit=$status (expected $expect_exit)"
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

# npm / npx 封じ (exit 1 + pnpm 誘導メッセージ)
run_case "npm-bare"           1 "npm"                  "pnpm を使ってください"
run_case "npm-with-args"      1 "npm install lodash"   "pnpm install"
run_case "npx-bare"           1 "npx"                  "pnpm dlx"
run_case "npx-with-args"      1 "npx cowsay hi"        "pnpm dlx"

# PNPM_HOME / fish_add_path 環境設定
run_case "pnpm-home-set"       0 'echo $PNPM_HOME'                                                    "^$WORKDIR\$"
# fish_add_path -g は $fish_user_paths を更新する。--no-config 環境では
# $PATH への再計算が発火しないため、$fish_user_paths を直接検証する
run_case "pnpm-bin-registered" 0 'contains $PNPM_HOME/bin $fish_user_paths; and echo REGISTERED'      "REGISTERED"
# fish_add_path は idempotent、二重 source しても fish_user_paths に重複しない
run_case "pnpm-bin-idempotent" 0 'source "'"$TARGET"'"; count (string match -a -- $PNPM_HOME/bin $fish_user_paths)' "^1\$"

# PNPM_HOME 未設定時のフォールバック値 ($HOME/.local/share/pnpm) を検証する。
# 上で export した PNPM_HOME を env -u で削り、pnpm.fish の or 分岐を実行させる
fallback_out=$(env -u PNPM_HOME fish --no-config -c "source '$TARGET'; echo \$PNPM_HOME" 2>&1)
fallback_status=$?
fallback_expected="$HOME/.local/share/pnpm"
if [ "$fallback_status" -eq 0 ] && [ "$fallback_out" = "$fallback_expected" ]; then
  pass=$((pass+1))
else
  echo "FAIL pnpm-home-fallback: exit=$fallback_status output=$fallback_out (expected $fallback_expected)"
  fail=$((fail+1))
fi

echo "fish-pnpm tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
