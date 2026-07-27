#!/usr/bin/env bash
# fish/config/rbenv.fish・pyenv.fish の回帰テスト。
#
# ツールごとの検証項目 (rbenv / pyenv で同一。件数の合計はハードコードせず
# 末尾の `N passed, N failed` 行で確認する — ケース追加のたびに数値が drift
# するため):
#   1. ガード: ツールが PATH に無い環境で source しても
#      - exit 0 で通る
#      - shell function が定義されない (`type -q` ガードが効いている)
#      - **出力が完全に無い**
#      3 つ目が本体。ガードを外しても exit は 0 のままで function も定義され
#      ないため、出力の有無を見ないとガードの欠落を検出できない (mutation
#      check で確認済み)。実際に観測される害は fish 起動ごとに
#      `fish: Unknown command: pyenv` が stderr に出ること。
#      なお fish は source 先の構文エラーでも exit 0 のまま stderr に出すため、
#      このケースは構文エラーの混入も同時に拾う。
#   2. 配線 (stub): PATH に stub を仕込み、init 経由で shell function が
#      定義されること + **stub が受け取った引数が `init - fish` であること**を
#      検証する (集計は 2 カウント)。ホストへの rbenv/pyenv インストールに
#      依存しない。引数 assert により `-` 落ち (rbenv では shell 初期化
#      ファイルを書き換えに行く破壊的 typo) を検出できる。
#   3. root 不変条件 (2 ケース): `RBENV_ROOT` / `PYENV_ROOT` を一切変更しない
#      こと。詳細は下部 root_snippet のコメントを参照。
#   4. 実物 (任意): ホストに本物が実在する場合のみ、実際の init が
#      function を定義することを確認する。未実在ならこのケースだけ skip。
#
# 依存: fish (未インストールなら全体を skip)
# 注意: .github/workflows/ は fish を install していないため、現状この
# スイートは CI では全体 skip される。stub 化で rbenv/pyenv 非依存には
# なったが、CI で実際に走らせるには workflow 側に fish の追加が要る。
#
# `set -e` は使わない: run_case が fish の exit code を自分で見て
# pass/fail を集計するため、非 0 で即終了されると集計できない。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"

if ! command -v fish >/dev/null 2>&1; then
  echo "SKIP fish-version-managers tests: fish 未インストール"
  exit 0
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/fish-version-managers.XXXXXX")" || {
  echo "ERROR: mktemp -d failed" >&2
  exit 1
}
trap 'rm -rf "$WORKDIR"' EXIT
mkdir -p "$WORKDIR/bin"

# fish を起動するときは HOME / XDG_CONFIG_HOME を WORKDIR 配下に逃がす。
# 実物ケースは PATH に本物の rbenv / pyenv が乗った状態で対象ファイルを source
# するため、万一 `rbenv init` から `-` が落ちる回帰が入ると rbenv は
# 「シェル初期化ファイルを書き換える」モードで走る。~/.config/fish は repo の
# fish/ への symlink なので、隔離しないとテスト実行が tracked file を破壊する
# (実際に PR #222 の開発中に発生した)。書き込み先が XDG_CONFIG_HOME 配下に
# 限定されることは実測で確認済み。
mkdir -p "$WORKDIR/home/.config/fish"

pass=0
fail=0

# snippet は成否を exit code で表現する (期待値は常に 0)。
# expect_silent=1 のとき stdout/stderr が完全に空であることも要求する。
# 第 4 引数以降は `env` へそのまま渡す追加の環境変数代入 (省略可)。既定値の
# 後ろに置くので、同じ変数を渡せば後勝ちで上書きできる (BSD/GNU 共通挙動)。
#
# `-u RBENV_ROOT -u PYENV_ROOT` は全ケース共通の既定にしてある:
#   - テスト実行者のシェルに ROOT が export されていても全ケースを隔離するため
#   - `ROOT=""` を渡す方式では代用できない。fish からは「空文字で set 済み」に
#     見えるため、`set -q ROOT` だけをガードにした分岐の再導入 (root 不変条件の
#     mutant b) を検出できなくなる
#   - BSD env は代入オペランドより後に `-u` を置けないため、位置を固定できる
#     既定側でしか指定できない (後から `ROOT=...` で上書きするのは可)
run_case() {
  local name="$1" expect_silent="$2" snippet="$3"
  shift 3
  local combined status
  # `${1+"$@"}` は bash 3.2 + `set -u` で引数 0 個の `"$@"` が unbound 扱いに
  # なる問題の回避 (bash 4.4 で挙動が修正された)。
  combined=$(env -u RBENV_ROOT -u PYENV_ROOT \
    HOME="$WORKDIR/home" XDG_CONFIG_HOME="$WORKDIR/home/.config" \
    ${1+"$@"} \
    fish --no-config -c "$snippet" 2>&1)
  status=$?
  if [ "$status" -ne 0 ]; then
    echo "FAIL $name: exit=$status (expected 0)"
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

# 呼ばれた引数を argv ファイルに記録し、fish 用 init スクリプトを stdout に出す stub。
# 本物と同じく `function <tool>` を定義する出力を返すので、config 側の
# `<tool> init - fish | source` がそのまま通る。
make_stub() {
  local tool="$1"
  cat > "$WORKDIR/bin/$tool" <<STUB
#!/bin/sh
printf '%s\n' "\$*" > "$WORKDIR/$tool.argv"
printf 'function %s\n    echo stub\nend\n' "$tool"
STUB
  chmod +x "$WORKDIR/bin/$tool"
}

# root 不変条件ケースの fish snippet を組み立てる。
#
# 以前の rbenv.fish は「keg 配下に versions の実体があれば RBENV_ROOT を keg に
# 向ける」分岐を持っていたが、keg は `brew upgrade rbenv` で丸ごと消えるため
# 配置そのものが誤りだった (issue #219)。分岐を削除した今、検証すべき不変条件は
# 「<tool>.fish は <TOOL>_ROOT を一切変更しない」。pyenv.fish も同じ前提を
# コメントで宣言しているため同一形状のケースを張る。旧分岐が最も発火しやすかった
# 条件 (keg に実体あり / default root は空) を fixture で再現して assert する。
# これが無いと分岐が再導入されても他ケースは green のままになる。
#
# `functions -q` ガードは飾りではない: fish は source の失敗 (パスの typo /
# ファイル移動) でも exit 0 のまま後続を実行するため、値だけを見ると「一度も
# source されていない」ケースが「未設定」と区別できず vacuous pass になる。
# ガードは stub が定義する function の有無を条件にしているので、source が
# 通っていなければ `NOT SOURCED` を出して FAIL する。
# 不一致時に実値を echo してから exit 1 するのは、run_case が FAIL 時に
# combined を stderr へ出すため — 原因の切り分けに手動再現が要らなくなる。
root_snippet() {
  local tool="$1" target="$2" root_var="$3" expected="$4"
  printf '%s\n' \
    "set -gx PATH '$WORKDIR/bin'" \
    "source '$target'" \
    "if not functions -q $tool" \
    "    echo 'NOT SOURCED'" \
    "    exit 1" \
    "end" \
    "if test \"\$$root_var\" = '$expected'" \
    "    exit 0" \
    "end" \
    "echo \"$root_var=\$$root_var\"" \
    "exit 1"
}

for tool in rbenv pyenv; do
  target="$REPO_ROOT/fish/config/$tool.fish"
  if [ ! -f "$target" ]; then
    echo "ERROR: $target が見つからない" >&2
    exit 1
  fi
  # `${var^^}` は bash 4 以降なので使えない (macOS 標準は 3.2)。
  # LC_ALL=C pin は tr のケース変換をロケール非依存にするため。
  root_var="$(printf '%s' "$tool" | LC_ALL=C tr '[:lower:]' '[:upper:]')_ROOT"

  # 1. ガード: PATH を空 dir だけにすると `type -q` が偽になる。
  #    exit 0 / function 未定義 / 無出力 の 3 点を同時に検証する。
  #    (function が定義されてしまったら `functions -q` が真になり exit 1 で FAIL)
  #    /usr/bin や /bin ではなく空 dir を使うのは、システム由来の
  #    rbenv/pyenv がある host で誤 FAIL しないようにするため。
  mkdir -p "$WORKDIR/empty"
  run_case "$tool: PATH に不在なら無言で通りガードが効く" 1 \
    "set -gx PATH '$WORKDIR/empty'; source '$target'; if functions -q $tool; exit 1; end; exit 0"

  # 2. 配線: stub を PATH 先頭に置き、function が定義されることを検証する
  make_stub "$tool"
  rm -f "$WORKDIR/$tool.argv"
  run_case "$tool: stub 経由で shell function が定義される" 1 \
    "set -gx PATH '$WORKDIR/bin'; source '$target'; if functions -q $tool; exit 0; end; exit 1"

  # stub が受け取った引数を assert する (`-` 落ち等の回帰検出)
  if [ -f "$WORKDIR/$tool.argv" ]; then
    actual_argv=$(cat "$WORKDIR/$tool.argv")
    if [ "$actual_argv" = "init - fish" ]; then
      pass=$((pass + 1))
    else
      echo "FAIL $tool: init 引数が想定外: '$actual_argv' (expected 'init - fish')"
      fail=$((fail + 1))
    fi
  else
    echo "FAIL $tool: stub が呼ばれた形跡がない"
    fail=$((fail + 1))
  fi

  # 3. root 不変条件: <TOOL>_ROOT を一切変更しないこと。
  #    fixture は **現行の rbenv.fish / pyenv.fish からは参照されない**
  #    (versions を glob する行ごと削除済み)。「未使用だから」と消さないこと:
  #    旧分岐が再導入された mutant を発火させるために必要で、これが無いと
  #    mutant が「keg に実体が無い」と判定して素通りし、テストが再導入を
  #    検出できなくなる。
  mkdir -p "$WORKDIR/fx/keg/opt/$tool/versions/3.4.2"
  mkdir -p "$WORKDIR/fx/home-empty/.$tool/versions"

  # keg に実体があり default root が空でも ROOT を設定しない。
  # ROOT は run_case の既定 `env -u` で真に unset になっている。
  run_case "$tool root: keg に実体があっても $root_var を設定しない" 1 \
    "$(root_snippet "$tool" "$target" "$root_var" "")" \
    HOME="$WORKDIR/fx/home-empty" \
    XDG_CONFIG_HOME="$WORKDIR/fx/home-empty/.config" \
    HOMEBREW_PREFIX="$WORKDIR/fx/keg"

  # 外部で設定された ROOT はそのまま通す (config.local.fish は config.fish で
  # config/*.fish より先に source されるため実在する経路)。
  # 期待値が非空なので harness 破損の検出も兼ねる。
  run_case "$tool root: 外部の $root_var を潰さない" 1 \
    "$(root_snippet "$tool" "$target" "$root_var" "/custom/$tool")" \
    HOME="$WORKDIR/fx/home-empty" \
    XDG_CONFIG_HOME="$WORKDIR/fx/home-empty/.config" \
    HOMEBREW_PREFIX="$WORKDIR/fx/keg" \
    "$root_var=/custom/$tool"

  # 4. 実物がホストにある場合のみ: 実際の init で function が定義される
  #    (出力の有無は見ない。pyenv の rehash は shims が書けない環境で
  #     stderr に出るため、host 条件に依存させない)
  if command -v "$tool" >/dev/null 2>&1; then
    run_case "$tool: 実物の init で shell function が定義される" 0 \
      "source '$target'; if functions -q $tool; exit 0; end; exit 1"
  else
    echo "SKIP $tool: ホストに未インストールのため実物テストを skip"
  fi
done

echo "fish-version-managers tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
