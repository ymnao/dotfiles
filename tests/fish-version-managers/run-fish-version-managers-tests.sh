#!/usr/bin/env bash
# fish/config/rbenv.fish・pyenv.fish・nodebrew.fish の回帰テスト。
#
# 検証対象は形が 2 つに分かれる:
#   - **init 型** (rbenv / pyenv): `<tool> init - fish | source` で shell
#     function を定義する。下の「ツールごとの検証項目」がこれ
#   - **PATH 追加型** (nodebrew): init 相当が無く `fish_add_path` だけ。
#     function を定義しないので init 型の検証項目 (function 定義 /
#     `init - fish` 引数 / `functions -q` を source 済みガードに使う root
#     不変条件) はどれも成立しない。TOOLS へ足すと全ケースが vacuous pass に
#     なるため、ループを共有せず別セクションに分けてある (下部参照)
#
# ツールごとの検証項目 (rbenv / pyenv で同一。件数の合計はハードコードせず
# 末尾の `N passed, N failed` 行で確認する — ケース追加のたびに数値が drift
# するため。ただし末尾に「必須ケースが実行されたか」の floor があり、そこは
# ツールあたりの必須ケース数を持っている。必須ケースを増減したら
# MANDATORY_PER_TOOL も更新すること):
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
# 任意ケース (実物の init) が何件走ったか。末尾の floor から差し引くために
# 数える — floor が pass 合計を見ると、実物が入っているホストでは任意ケースの
# pass が必須ケースの欠落を埋めて素通りする。
optional_ran=0

# 検証対象のツールと、その root 変数。**同じ添字が対応する並行配列**で持つ。
# 変数名を tool 名から機械的に導出しないのは、導出が外れたとき root 不変条件
# ケースが FAIL せず vacuous pass するため — 存在しない変数名になると
# 「未設定を期待 → 誰も設定しないので pass」「外部値を期待 → env で入れた値を
# 読み返すので pass」となり、config を一切見ないまま green になる
# (ASDF_DATA_DIR / NVM_DIR のように `<TOOL>_ROOT` 規則から外れるツールで実際に
# 起きる)。ROOT_VARS はそのまま全ケースの `env -u` 対象にもなるので、
# 「隔離リスト」と「検証対象」が食い違う経路自体が存在しない。
TOOLS=(rbenv pyenv)
ROOT_VARS=(RBENV_ROOT PYENV_ROOT)

# 並行配列の対応が崩れると (長さ違い / 並びの取り違え) 上記の vacuous pass に
# 戻るため、2 つの assert で塞ぐ。規則から外れるツールを足すときは
# ROOT_VAR_EXCEPTIONS にその tool 名を空白区切りで書く。
ROOT_VAR_EXCEPTIONS=""
if [ "${#TOOLS[@]}" -ne "${#ROOT_VARS[@]}" ]; then
  echo "ERROR: TOOLS と ROOT_VARS の長さが違う (対応が崩れている)" >&2
  exit 1
fi

# `env -u` に渡す引数。全ケースで不変なので一度だけ組み立てる。
UNSET_ARGS=()
for root_var in "${ROOT_VARS[@]}"; do
  UNSET_ARGS+=(-u "$root_var")
done

# snippet は成否を exit code で表現する (期待値は常に 0)。
# expect_silent=1 のとき stdout/stderr が完全に空であることも要求する。
# 第 4 引数以降は `env` へそのまま渡す追加の環境変数代入 (省略可)。既定値の
# 後ろに置くので、同じ変数を渡せば後勝ちで上書きできる (BSD env で実測。GNU も
# 同順で putenv する実装だが、このホストでは未検証)。
#
# ROOT_VARS の `-u` を全ケース共通の既定にしてあるのは:
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
  combined=$(env "${UNSET_ARGS[@]}" \
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

# fish を起動しない値比較 1 件を集計する。pass/fail カウンタと FAIL 判定経路を
# run_case と共有するために関数化してある (集計が 2 通り並存すると、片方だけ
# 直る drift が起きる — issue #221)。名前・引数順・書式は repo の既存実装
# (tests/link-backup/ tests/locale-matrix/ の assert_eq) に合わせて want を先に
# 取る。引数順の取り違えは FAIL にならず発見が遅れるため揃える価値がある。
assert_eq() {
  local name="$1" want="$2" got="$3"
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
    return
  fi
  echo "FAIL $name: want=[$want] got=[$got]"
  fail=$((fail + 1))
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
# 「<tool>.fish は <TOOL>_ROOT を一切変更しない」。pyenv.fish はこの分岐を
# 持ったことは一度も無いが、同じ前提をコメントで宣言しているため同一形状の
# ケースを張る (rbenv が踏んだ #219 と同型の再発防止)。旧分岐が最も発火し
# やすかった条件 (keg に実体あり / default root は空) を fixture で再現して
# assert する。これが無いと分岐が再導入されても他ケースは green のままになる。
#
# 期待値が空のケースは値比較ではなく `set -q` で **set されていないこと**を
# 要求する。fish では unset と空文字 set が quoted 展開で区別できないため、
# 値比較だと `set -gx <VAR> ""` する mutant を取りこぼす。
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
    "end"
  if [ -z "$expected" ]; then
    printf '%s\n' \
      "if set -q $root_var" \
      "    echo \"$root_var is set: '\$$root_var'\"" \
      "    exit 1" \
      "end" \
      "exit 0"
  else
    printf '%s\n' \
      "if test \"\$$root_var\" = '$expected'" \
      "    exit 0" \
      "end" \
      "echo \"$root_var=\$$root_var\"" \
      "exit 1"
  fi
}

for ((i = 0; i < ${#TOOLS[@]}; i++)); do
  tool="${TOOLS[$i]}"
  root_var="${ROOT_VARS[$i]}"
  target="$REPO_ROOT/fish/config/$tool.fish"
  if [ ! -f "$target" ]; then
    echo "ERROR: $target が見つからない" >&2
    exit 1
  fi
  # 並行配列の並びを取り違えると (rbenv に PYENV_ROOT を対応付ける等)、
  # 対象 config を一切見ないまま 2 ケースとも pass する。規則どおりのツールは
  # `<TOOL>_ROOT` との一致を assert して塞ぐ。`asdf` (ASDF_DATA_DIR) のように
  # 規則から外れるツールは ROOT_VAR_EXCEPTIONS に明示して免除する。
  # `${var^^}` は bash 4 以降なので tr を使う (LC_ALL=C pin でロケール非依存)。
  case " $ROOT_VAR_EXCEPTIONS " in
    *" $tool "*) ;;
    *)
      expected_root_var="$(printf '%s' "$tool" | LC_ALL=C tr '[:lower:]' '[:upper:]')_ROOT"
      if [ "$root_var" != "$expected_root_var" ]; then
        echo "ERROR: $tool の root 変数が $root_var ($expected_root_var を期待。" \
          "規則から外れるなら ROOT_VAR_EXCEPTIONS に追加すること)" >&2
        exit 1
      fi
      ;;
  esac

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

  # stub が受け取った引数を assert する (`-` 落ち等の回帰検出)。
  # argv ファイルが無い = stub が一度も呼ばれていないので、その旨を実値として
  # 流し込み FAIL 経路を assert_eq に一本化する。
  if [ -f "$WORKDIR/$tool.argv" ]; then
    actual_argv=$(cat "$WORKDIR/$tool.argv")
  else
    actual_argv="(stub が呼ばれた形跡なし)"
  fi
  assert_eq "$tool: stub が受け取った init 引数" "init - fish" "$actual_argv"

  # 3. root 不変条件: <TOOL>_ROOT を一切変更しないこと。
  #    fixture は **現行の rbenv.fish / pyenv.fish からは参照されない**
  #    (versions を glob する行ごと削除済み)。「未使用だから」と消さないこと:
  #    旧分岐が再導入された mutant を発火させるために必要で、これが無いと
  #    mutant が「keg に実体が無い」と判定して素通りし、テストが再導入を
  #    検出できなくなる。
  mkdir -p "$WORKDIR/fx/keg/opt/$tool/versions/3.4.2"
  mkdir -p "$WORKDIR/fx/home-empty/.$tool/versions"
  # 他ケースの隔離 HOME と同じく設定ディレクトリも作っておく (不在だと fish の
  # 版によっては warning が stderr に出て expect_silent=1 のこのケースだけ落ちる)
  mkdir -p "$WORKDIR/fx/home-empty/.config/fish"
  # 2 ケースで共有する fixture 環境。片方だけパスを直す drift を防ぐため
  # 1 箇所にまとめる。
  root_env=(
    HOME="$WORKDIR/fx/home-empty"
    XDG_CONFIG_HOME="$WORKDIR/fx/home-empty/.config"
    HOMEBREW_PREFIX="$WORKDIR/fx/keg"
  )

  # keg に実体があり default root が空でも ROOT を設定しない。
  # ROOT は run_case の既定 `env -u` で真に unset になっている。
  run_case "$tool root: keg に実体があっても $root_var を設定しない" 1 \
    "$(root_snippet "$tool" "$target" "$root_var" "")" \
    "${root_env[@]}"

  # 外部で設定された ROOT はそのまま通す (config.local.fish は config.fish で
  # config/*.fish より先に source されるため実在する経路)。
  # 期待値が非空なので harness 破損の検出も兼ねる。
  run_case "$tool root: 外部の $root_var を潰さない" 1 \
    "$(root_snippet "$tool" "$target" "$root_var" "/custom/$tool")" \
    "${root_env[@]}" "$root_var=/custom/$tool"

  # 4. 実物がホストにある場合のみ: 実際の init で function が定義される
  #    (出力の有無は見ない。pyenv の rehash は shims が書けない環境で
  #     stderr に出るため、host 条件に依存させない)
  if command -v "$tool" >/dev/null 2>&1; then
    run_case "$tool: 実物の init で shell function が定義される" 0 \
      "source '$target'; if functions -q $tool; exit 0; end; exit 1"
    optional_ran=$((optional_ran + 1))
  else
    echo "SKIP $tool: ホストに未インストールのため実物テストを skip"
  fi
done

# ---------------------------------------------------------------------------
# PATH 追加型: nodebrew (issue #218)
#
# ケース 1-3 が見るのは PATH ではなく **fish_user_paths**。`--no-config` では
# fish_user_paths を PATH へ反映する handler が入らないため。同じ制約と
# assert の形が tests/fish-pnpm/run-fish-pnpm-tests.sh の
# pnpm-bin-registered / pnpm-bin-idempotent にもある — fish 側の挙動が
# 変わったら**両方**直すこと。PATH 上の実順序と変数スコープは
# `--no-config` では見えないので、下の実 config ケース (5) で見る。
#
# 検出できる mutant / できない mutant を明示しておく:
#   - `--path` 直操作 / `set -a PATH` → ケース 2・3 が落ちる
#   - `-g` 落ち (universal 化) → ケース 1-3 では**落ちない**。`--no-config`
#     は universal 自体を無効化するので構造的に検出不能。ケース 5 が
#     fish_variables の生成有無で拾う
#   - `-a` (append) → 落ちない。落とす必要も無い (Homebrew との前後は
#     変わらない。理由は fish/config/nodebrew.fish のコメント)
#
# ケース 1・4 (不在 / 壊れた symlink) が検証するのは fish_add_path の
# 「存在しないディレクトリを無視する」挙動への依存。nodebrew.fish は
# `test -d` ガードを持たず、この挙動に乗って未インストール時の無害性を
# 得ているため、fish 側が変わったらここで落ちる必要がある。
# fish から見た経路は両者同じ (`realpath -s` 後の `test -d` が偽) だが、
# 「入れたが `nodebrew use` 未実行」は実在する状態なので別ケースで持つ。
# ケース 1・4 は単独では vacuous pass しうる (source が届いていなくても
# 「追加されない」は成立する) が、同じ $nodebrew_target を使うケース 2 が
# 落ちること + 下の存在チェックで塞いでいる。
nodebrew_target="$REPO_ROOT/fish/config/nodebrew.fish"
if [ ! -f "$nodebrew_target" ]; then
  echo "ERROR: $nodebrew_target が見つからない" >&2
  exit 1
fi

# セクション単位の floor 用に、入る前の実行数を控える。末尾の総計 floor だけだと
# 「nodebrew の必須ケースを消して init 型に同数足す」相殺が素通りする。
nb_start=$((pass + fail))
nb_optional=0

# fixture: 未インストール / インストール済み / 壊れた current symlink の 3 種。
# 隔離 HOME には設定ディレクトリも作る (不在だと fish の版によっては warning が
# stderr に出て expect_silent=1 のケースだけ落ちる)。
#
# インストール済み fixture は実機と同じ形にする — `current` は
# `node/<version>` への symlink で、実ディレクトリではない。`nodebrew use` の
# 切替が効くのは fish_add_path が symlink を解決せず `current/bin` のまま
# 登録するから (実装は `builtin realpath -s`、man も "symlinks are not
# resolved")。実ディレクトリの fixture だと、解決する実装に変わっても
# ケース 2 が素通りしてこの前提が守られない。
nb_present_version=v22.14.0
mkdir -p "$WORKDIR/nb/absent/.config/fish"
mkdir -p "$WORKDIR/nb/present/.nodebrew/node/$nb_present_version/bin" \
  "$WORKDIR/nb/present/.config/fish"
ln -sfn "$WORKDIR/nb/present/.nodebrew/node/$nb_present_version" \
  "$WORKDIR/nb/present/.nodebrew/current"
mkdir -p "$WORKDIR/nb/broken/.nodebrew" "$WORKDIR/nb/broken/.config/fish"
ln -sfn "$WORKDIR/nb/broken/.nodebrew/node/v0.0.0" "$WORKDIR/nb/broken/.nodebrew/current"

# ケース 1・4 は fixture (HOME) だけが違い snippet は同一なので 1 度だけ組む。
# 片方の assert だけ直して drift するのを防ぐ。
nb_expect_nothing_added="$(printf '%s\n' \
  "source '$nodebrew_target'" \
  'if set -q fish_user_paths[1]' \
  '    echo "fish_user_paths=$fish_user_paths"' \
  '    exit 1' \
  'end' \
  'exit 0')"

# 1. 未インストール: 何も追加せず無言で通る
run_case "nodebrew: ~/.nodebrew が無ければ何も追加しない" 1 \
  "$nb_expect_nothing_added" \
  "HOME=$WORKDIR/nb/absent" "XDG_CONFIG_HOME=$WORKDIR/nb/absent/.config"

# 2. 配線: current/bin があれば fish_user_paths に入る。fixture の current は
#    symlink なので、登録値が `current/bin` のまま (解決されて
#    `node/<version>/bin` になっていない) ことも同時に assert している
run_case "nodebrew: current/bin を解決せず fish_user_paths に追加する" 1 \
  "$(printf '%s\n' \
    "source '$nodebrew_target'" \
    'if contains -- "$HOME/.nodebrew/current/bin" $fish_user_paths' \
    '    exit 0' \
    'end' \
    'echo "fish_user_paths=$fish_user_paths"' \
    'exit 1')" \
  "HOME=$WORKDIR/nb/present" "XDG_CONFIG_HOME=$WORKDIR/nb/present/.config"

# 3. idempotent: 2 回 source しても 1 本しか増えない
#    (config.local.fish 等から二重に読まれても PATH が伸び続けない)
#    数えるのは配列全長ではなく**一致した要素数** (pnpm-bin-idempotent と
#    同じ形)。全長を見ると、将来 nodebrew.fish が正当な 2 本目を足しただけで
#    落ちてしまい、重複検査として読めなくなる
run_case "nodebrew: 2 回 source しても重複追加されない" 1 \
  "$(printf '%s\n' \
    "source '$nodebrew_target'" \
    "source '$nodebrew_target'" \
    'set -l n (count (string match -a -- "$HOME/.nodebrew/current/bin" $fish_user_paths))' \
    'if test $n -eq 1' \
    '    exit 0' \
    'end' \
    'echo "count=$n fish_user_paths=$fish_user_paths"' \
    'exit 1')" \
  "HOME=$WORKDIR/nb/present" "XDG_CONFIG_HOME=$WORKDIR/nb/present/.config"

# 4. 壊れた current symlink: nodebrew を入れただけで `nodebrew use` 未実行の
#    状態。`test -d` は symlink を辿るので追加されない
run_case "nodebrew: current が壊れた symlink なら何も追加しない" 1 \
  "$nb_expect_nothing_added" \
  "HOME=$WORKDIR/nb/broken" "XDG_CONFIG_HOME=$WORKDIR/nb/broken/.config"

# 5. 実 config を login shell で起こす。1 回の起動から 2 つを見る:
#    (a) 必須 — universal 変数 (fish_variables) を作らないこと。`-g` 落ちの
#        検出点はここしか無い (`--no-config` のケース 1-3 では universal が
#        無効化されるため構造的に検出できない)。実害は「repo 管理外の永続
#        状態が残り、nodebrew.fish を消しても PATH に残り続ける」
#    (b) 任意 — PATH 上で ~/.nodebrew/current/bin が /opt/homebrew/bin より
#        前に来ること。issue #218 の受け入れ条件そのものだが Homebrew の
#        有無に依存するので任意扱い (optional_ran に数えて floor から差し引く)
#
#    fish/ は symlink ではなく **コピー**して渡す: 隔離 HOME の
#    XDG_CONFIG_HOME を repo の fish/ に向けると、rbenv init の `-` 落ち
#    回帰が入ったときに tracked file が書き換わる (上部コメント参照)。
#    config.fish を最小 fixture に差し替えれば starship / rbenv / pyenv 等の
#    init を起こさずに済むが、それをやると**実 config を検査しなくなる**:
#    別の config/*.fish が後から PATH を割り込ませる回帰は最小 fixture では
#    再現しない。このケースの価値はそこにあるので実物を使う (スイート全体で
#    実測 1.2 秒)。
mkdir -p "$WORKDIR/e2e/home/.nodebrew/node/$nb_present_version/bin" \
  "$WORKDIR/e2e/home/.config"
ln -sfn "$WORKDIR/e2e/home/.nodebrew/node/$nb_present_version" \
  "$WORKDIR/e2e/home/.nodebrew/current"
cp -R "$REPO_ROOT/fish" "$WORKDIR/e2e/home/.config/fish"
printf '%s\n' 'for p in $PATH' 'echo $p' 'end' > "$WORKDIR/e2e/show.fish"
e2e_out=$(env "${UNSET_ARGS[@]}" \
  HOME="$WORKDIR/e2e/home" XDG_CONFIG_HOME="$WORKDIR/e2e/home/.config" \
  fish -l "$WORKDIR/e2e/show.fish" 2>/dev/null)

# (a) 必須: universal 変数が永続化されていないこと。
#     `-g` を落とすと fish_add_path は universal を既定にするため
#     $XDG_CONFIG_HOME/fish/fish_variables が生成される (実測で確認済み)。
if [ -e "$WORKDIR/e2e/home/.config/fish/fish_variables" ]; then
  e2e_universal=created
else
  e2e_universal=absent
fi
assert_eq "nodebrew: 実 config で universal 変数を永続化しない" absent "$e2e_universal"

# (b) 任意: Homebrew との前後関係
if [ -d /opt/homebrew/bin ]; then
  # grep -n -x -F で完全一致行の行番号を取る (部分一致だと
  # /opt/homebrew/bin と /opt/homebrew/sbin を取り違える)
  nb_line=$(printf '%s\n' "$e2e_out" \
    | grep -n -x -F "$WORKDIR/e2e/home/.nodebrew/current/bin" | head -1 | cut -d: -f1)
  hb_line=$(printf '%s\n' "$e2e_out" | grep -n -x -F "/opt/homebrew/bin" | head -1 | cut -d: -f1)
  if [ -n "$nb_line" ] && [ -n "$hb_line" ] && [ "$nb_line" -lt "$hb_line" ]; then
    order_result=ordered
  else
    order_result="nodebrew=${nb_line:-none} homebrew=${hb_line:-none}"
  fi
  assert_eq "nodebrew: 実 config で /opt/homebrew/bin より前に来る" ordered "$order_result"
  optional_ran=$((optional_ran + 1))
  nb_optional=$((nb_optional + 1))
else
  echo "SKIP nodebrew: /opt/homebrew/bin が無いため実 config の順序テストを skip"
fi

# PATH 追加型セクションの必須 5 件: 不在 / 配線 / idempotent / 壊れた symlink /
# universal 非永続化。期待値は独立リテラルで持ち、ケース数から導出しない
# (claude/rules/shell.md の floor 規約)。
MANDATORY_PATH_CASES=5
nb_ran=$(( pass + fail - nb_start - nb_optional ))
if [ "$nb_ran" -lt "$MANDATORY_PATH_CASES" ]; then
  echo "FAIL: nodebrew の必須ケースが実行されていない ($nb_ran < $MANDATORY_PATH_CASES)" >&2
  exit 1
fi

echo "fish-version-managers tests: $pass passed, $fail failed"

# ケースが黙って実行されなくなっても fail は 0 のままなので、必須ケースが
# 実行された件数に floor を張る。3 点に注意して組んでいる:
#   - 数えるのは pass ではなく **実行数** (pass + fail)。pass を見ると
#     「実行されたが FAIL した」まで「実行されていない」と誤って報告する
#   - 任意ケース (実物の init) の分は差し引く。含めると、実物が入っている
#     ホストでは任意ケースの pass が必須ケースの欠落を埋めて素通りする
#   - 期待ツール集合は TOOLS から導出せず独立に持つ。floor が守る対象そのもの
#     から導出すると、TOOLS からツールを落としたとき floor も一緒に下がる
# 必須は init 型 1 ツールあたり 5 件: ガード / stub function / argv assert /
# root 不変条件 2 件。
MANDATORY_PER_TOOL=5
EXPECTED_TOOLS="rbenv pyenv"
if [ "${TOOLS[*]}" != "$EXPECTED_TOOLS" ]; then
  echo "FAIL: 検証対象ツールが変わっている (TOOLS='${TOOLS[*]}' expected '$EXPECTED_TOOLS')" >&2
  exit 1
fi
# PATH 追加型 (nodebrew) の分はセクション末尾で独立に floor を張ってあるので、
# ここでは総計に足すだけ (セクション間の相殺はそちらが検出する)。
mandatory_ran=$(( pass + fail - optional_ran ))
required_ran=$(( ${#TOOLS[@]} * MANDATORY_PER_TOOL + MANDATORY_PATH_CASES ))
if [ "$mandatory_ran" -lt "$required_ran" ]; then
  echo "FAIL: 必須ケースが実行されていない ($mandatory_ran < $required_ran)" >&2
  exit 1
fi

[ "$fail" -eq 0 ]
