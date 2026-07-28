#!/usr/bin/env bash
# -e を外している: このスイートは検査対象の**非 0 終了そのもの**を期待値と
# して検証する (checksum 不一致 / curl 失敗 / 展開失敗 / install 失敗)。
# -e を付けると run_script の非 0 終了でランナー自身が死に、失敗経路の
# ケースが 1 つも検証できなくなる。exit code は `|| rc=$?` で受ける。
set -uo pipefail

# 文字列比較と grep をバイト同一性で行うためロケールを固定する
# (claude/rules/shell.md)。診断メッセージの assert が ambient ロケールで
# ゆらぐのを防ぐ。検査対象スクリプト自身も LC_ALL=C を export している。
export LC_ALL=C

# .github/scripts/install-shellcheck.sh の回帰テスト (issue #232)。
#
# 何を守るテストか: このスクリプトは外部バイナリ (shellcheck) を取得して
# PATH に置く CI 用インストーラで、SHA256 検証がサプライチェーンの唯一の
# 関門になっている。正常系は CI が走るたびに通るが、**失敗経路はどこからも
# 実行されない**ため、checksum 検証が静かに無効化されても green が続く。
#
# 方式: uname / curl / sha256sum / shasum / tar / install を PATH 上の
# スタブに差し替え、HOME と TMPDIR と GITHUB_PATH / GITHUB_ENV を
# テスト専用に差し替えて全分岐をネットワーク非依存で回す
# (tests/verify-ci/run-verify-ci-tests.sh の gh / curl スタブ方式と同型)。
#
# PATH を `env -i` + 最小 PATH で完全に組み直しているのが要点。`/usr/bin` を
# 残すと Linux では実 sha256sum が、macOS では実 shasum が見えてしまい、
# 検査対象の `command -v sha256sum` 分岐を**ホスト非依存に制御できない**
# (どちらの経路を通ったかがテスト実行機によって変わる)。
#
# 限界: スタブは curl / tar の応答を固定するため、実 GitHub Releases の
# レイアウト変更や tar.xz の実展開結果は検出できない (そこは CI の実行が
# 検証する)。ここが守るのは分岐とガードの構造であって取得内容ではない。
#
# 依存: bash 3.2+ / git。curl・tar・shellcheck は不要 (スタブを使う)。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
TARGET="${INSTALL_SHELLCHECK_PATH:-$REPO_ROOT/.github/scripts/install-shellcheck.sh}"

if [ ! -f "$TARGET" ]; then
  echo "ERROR: target not found: $TARGET (INSTALL_SHELLCHECK_PATH で上書き可)" >&2
  exit 1
fi

# bash の絶対パスを先に解決する。`env -i PATH=... bash ...` は **env が
# 差し替え後の PATH で bash を解決する**ため、最小 PATH に bash を含めない
# 構成では絶対パス指定が必須になる。
BASH_BIN="$(command -v bash)"
if [ -z "$BASH_BIN" ]; then
  echo "ERROR: bash not found in PATH" >&2
  exit 1
fi

# --- 検査対象から定数を抽出 ---------------------------------------------
# テスト側に SHA / VERSION のリテラルを持つと、bump 時に必ず二重管理の
# drift になる (片方だけ更新されるとテストが偽 fail か偽 pass になる)。
# 抽出が空になったら fail-open させずここで即死させる — 変数名のリネームで
# 抽出が外れたまま「期待 SHA が空文字」で回ると、checksum ケースが
# 意味を失ったまま pass しうる。
extract_const() {
  # $1=変数名, $2=値の正規表現
  local name="$1" pattern="$2" value count
  value="$(grep -E "^${name}=\"${pattern}\"\$" "$TARGET" | cut -d'"' -f2)"
  count="$(printf '%s' "$value" | grep -c . || true)"
  if [ -z "$value" ] || [ "$count" != "1" ]; then
    echo "ERROR: $TARGET から ${name} を一意に抽出できない (取得値: '${value}')" >&2
    exit 1
  fi
  printf '%s' "$value"
}

VERSION="$(extract_const VERSION 'v[0-9]+\.[0-9]+\.[0-9]+')"
SHA_LINUX="$(extract_const SHA256_LINUX_X86_64 '[0-9a-f]{64}')"
SHA_DARWIN="$(extract_const SHA256_DARWIN_AARCH64 '[0-9a-f]{64}')"

# checksum 不一致ケース用。実 SHA と衝突しない固定の 64 桁 hex。
WRONG_SHA="deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

BASE="$(mktemp -d "${TMPDIR:-/tmp}/install-shellcheck-tests.XXXXXX")"
cleanup() { [ -n "${BASE:-}" ] && rm -rf "$BASE"; }
trap cleanup EXIT

# --- 最小 PATH 用の実コマンド ------------------------------------------
# 検査対象が呼ぶ外部コマンドのうちスタブ化しないもの + スタブ自身が使うもの。
mkdir -p "$BASE/realbin"
for tool in mktemp cut mkdir install rm chmod; do
  tool_path="$(command -v "$tool")"
  if [ -z "$tool_path" ]; then
    echo "ERROR: required tool not found: $tool" >&2
    exit 1
  fi
  ln -s "$tool_path" "$BASE/realbin/$tool"
done

# --- スタブ実装 ---------------------------------------------------------
# 全て #!/bin/sh。制御は env 経由 (STUB_*) で行い、ケースごとに必要な
# バリアントを $BASE/stubs から case の bin ディレクトリへコピーする。
mkdir -p "$BASE/stubs"

cat >"$BASE/stubs/uname" <<'EOF'
#!/bin/sh
case "${1:-}" in
  -s) printf '%s\n' "$STUB_OS" ;;
  -m) printf '%s\n' "$STUB_ARCH" ;;
  *) echo "uname stub: unexpected args: $*" >&2; exit 90 ;;
esac
EOF

# curl: URL を完全一致で assert してから固定内容の偽 archive を書く。
# URL の assert は「platform 表が壊れて別 asset を取りに行く」退行の検出
# (verify-ci の curl スタブが endpoint と body を assert するのと同型)。
# 取得先ディレクトリ (= workdir) を STUB_CURL_LOG に記録するのは、
# cleanup 検証で「workdir が実在した」ことを先に確かめるため
# (記録が無いまま「残っていない」だけを見ると、mktemp より前に死んだ
# ケースでも pass する vacuous な検査になる)。
cat >"$BASE/stubs/curl" <<'EOF'
#!/bin/sh
out=""
url=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-o" ]; then out="$a"; fi
  prev="$a"
  url="$a"
done
if [ "$url" != "$STUB_EXPECT_URL" ]; then
  echo "curl stub: unexpected url: $url" >&2
  exit 91
fi
if [ -z "$out" ]; then
  echo "curl stub: missing -o" >&2
  exit 92
fi
printf '%s\n' "${out%/*}" >> "$STUB_CURL_LOG"
if [ -n "${STUB_CURL_FAIL:-}" ]; then
  exit 22
fi
printf 'fake-archive\n' > "$out"
EOF

# sha256sum / shasum: 実ファイルを読まず STUB_SHA_VALUE を返す。
# 検査対象は `| cut -d' ' -f1` で先頭フィールドを取るので出力形式を合わせる。
cat >"$BASE/stubs/sha256sum" <<'EOF'
#!/bin/sh
printf '%s  %s\n' "$STUB_SHA_VALUE" "${1:-}"
EOF

# shasum は `-a 256` 付きで呼ばれる契約。引数が変わったら落とす
# (フォールバック側だけアルゴリズム指定が落ちる退行の検出)。
cat >"$BASE/stubs/shasum" <<'EOF'
#!/bin/sh
if [ "${1:-}" != "-a" ] || [ "${2:-}" != "256" ]; then
  echo "shasum stub: expected '-a 256', got: $*" >&2
  exit 91
fi
printf '%s  %s\n' "$STUB_SHA_VALUE" "${3:-}"
EOF

# 呼ばれてはいけない経路に置く罠。sha256sum が在る環境で shasum 側へ
# 落ちる (またはその逆) 退行を、静かな pass ではなく異常終了で見せる。
cat >"$BASE/stubs/sha-trap" <<'EOF'
#!/bin/sh
echo "sha stub trap: この経路は呼ばれてはいけない: $0 $*" >&2
exit 92
EOF

# tar: 実 xz に依存せず、展開されたことにして偽 shellcheck を置く。
# 偽 shellcheck は実行可能かつ出力を持つ必要がある — 検査対象は末尾で
# `"${dest_dir}/shellcheck" --version` を実行するため。
cat >"$BASE/stubs/tar" <<'EOF'
#!/bin/sh
if [ "${1:-}" != "-xJf" ] || [ "${3:-}" != "-C" ]; then
  echo "tar stub: unexpected args: $*" >&2
  exit 90
fi
archive="$2"
dir="$4"
if [ ! -f "$archive" ]; then
  echo "tar stub: archive not found: $archive" >&2
  exit 90
fi
mkdir -p "${dir}/shellcheck-${STUB_VERSION}"
printf '#!/bin/sh\necho stub-shellcheck\n' > "${dir}/shellcheck-${STUB_VERSION}/shellcheck"
chmod +x "${dir}/shellcheck-${STUB_VERSION}/shellcheck"
EOF

cat >"$BASE/stubs/tar-fail" <<'EOF'
#!/bin/sh
echo "tar stub: simulated extraction failure" >&2
exit 1
EOF

cat >"$BASE/stubs/install-fail" <<'EOF'
#!/bin/sh
echo "install stub: simulated install failure" >&2
exit 1
EOF

chmod +x "$BASE/stubs"/*

pass=0
fail=0

check() {
  # $1=名前, $2=期待, $3=実際
  if [ "$3" = "$2" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $1: expected=$2 got=$3"
    fail=$((fail + 1))
  fi
}

check_contains() {
  # $1=名前, $2=ファイル, $3=期待する部分文字列
  if [ -f "$2" ] && grep -qF "$3" "$2"; then
    pass=$((pass + 1))
  else
    echo "FAIL $1: '$3' が $2 に含まれない"
    fail=$((fail + 1))
    [ -f "$2" ] && sed -n '1,20p' "$2" >&2
  fi
}

# ケース用の隔離ディレクトリを作る。$1=ケース名。
# HOME / TMPDIR / 出力先をケースごとに分けることで、前のケースの残骸が
# 次のケースの assert を汚さないようにする。
new_case() {
  local name="$1"
  mkdir -p "$BASE/$name/home" "$BASE/$name/tmp" "$BASE/$name/bin"
  printf '%s' "$BASE/$name"
}

# ケース bin にスタブを配置する。$1=ケースディレクトリ, 以降=`名前:実体` 対。
place_stubs() {
  local dir="$1" spec
  shift
  for spec in "$@"; do
    cp "$BASE/stubs/${spec#*:}" "$dir/bin/${spec%%:*}"
  done
}

# 期待 URL を組み立てる。$1=platform 文字列。
expect_url() {
  printf 'https://github.com/koalaman/shellcheck/releases/download/%s/shellcheck-%s.%s.tar.xz' \
    "$VERSION" "$VERSION" "$1"
}

# 検査対象を隔離環境で実行する。$1=ケースディレクトリ, 以降=追加の KEY=VALUE。
# stdout / stderr はケースディレクトリ配下に落とし、exit code を返す。
run_script() {
  local dir="$1" rc=0
  shift
  env -i \
    PATH="$dir/bin:$BASE/realbin" \
    HOME="$dir/home" \
    TMPDIR="$dir/tmp" \
    STUB_CURL_LOG="$dir/curl.log" \
    "$@" \
    "$BASH_BIN" "$TARGET" >"$dir/stdout" 2>"$dir/stderr" || rc=$?
  return "$rc"
}

# curl スタブが記録した workdir が削除されているかを返す ("gone" / "left" /
# "no-record")。"no-record" は curl 未到達 = cleanup を観測できていないこと
# を明示する値で、これを "gone" と同一視しないのが vacuous pass の予防。
workdir_state() {
  local dir="$1" recorded
  if [ ! -s "$dir/curl.log" ]; then
    printf 'no-record'
    return 0
  fi
  recorded="$(head -1 "$dir/curl.log")"
  if [ -d "$recorded" ]; then
    printf 'left'
  else
    printf 'gone'
  fi
}

# 複数行ファイルを 1 行表現に潰す。改行のまま check に渡すと FAIL 時の
# 診断が 1 行目までしか読めず、「expected と got が同じに見えるのに FAIL」
# という追跡不能なメッセージになる (append 退行の検出時に実際に起きた)。
flatten() {
  tr '\n' '|' <"$1"
}

installed_state() {
  # $1=ケースディレクトリ。設置物の有無と実行可否を 1 語で返す。
  local bin="$1/home/.local/bin/shellcheck"
  if [ ! -e "$bin" ]; then
    printf 'absent'
  elif [ -x "$bin" ]; then
    printf 'executable'
  else
    printf 'not-executable'
  fi
}

# =========================================================================
# case 1: 未対応 platform は download に進まず exit 1
# =========================================================================
# curl スタブを置いた上で「呼ばれていないこと」を curl.log の不在で見る。
# platform 判定が退行して case を素通りしたときに、ここが検出点になる。
c1="$(new_case unsupported-platform)"
place_stubs "$c1" uname:uname curl:curl
rc=0
run_script "$c1" STUB_OS=FooOS STUB_ARCH=riscv64 STUB_EXPECT_URL=unused || rc=$?
check "unsupported-platform-exit" 1 "$rc"
check_contains "unsupported-platform-stderr" "$c1/stderr" "unsupported platform: FooOS/riscv64"
check "unsupported-platform-no-download" "absent" "$([ -f "$c1/curl.log" ] && printf 'called' || printf 'absent')"

# =========================================================================
# case 2: 正常系 (Linux/x86_64, sha256sum 経路, GITHUB_PATH/ENV 設定済み)
# =========================================================================
# shasum を罠にしてあるので、sha256sum 優先の分岐が退行して shasum 側へ
# 落ちると exit 92 で落ち、このケースが FAIL する。
c2="$(new_case happy-linux)"
place_stubs "$c2" uname:uname curl:curl sha256sum:sha256sum shasum:sha-trap tar:tar
printf '/pre/existing/path\n' >"$c2/github_path"
printf 'PRE_EXISTING=1\n' >"$c2/github_env"
rc=0
run_script "$c2" \
  STUB_OS=Linux STUB_ARCH=x86_64 \
  STUB_EXPECT_URL="$(expect_url linux.x86_64)" \
  STUB_SHA_VALUE="$SHA_LINUX" \
  STUB_VERSION="$VERSION" \
  GITHUB_PATH="$c2/github_path" \
  GITHUB_ENV="$c2/github_env" || rc=$?
check "happy-linux-exit" 0 "$rc"
check "happy-linux-installed" "executable" "$(installed_state "$c2")"
# GITHUB_PATH / GITHUB_ENV は追記 (append) であり既存行を壊さないこと。
check "happy-linux-github-path" \
  "/pre/existing/path|$c2/home/.local/bin|" \
  "$(flatten "$c2/github_path")"
check "happy-linux-github-env" \
  "PRE_EXISTING=1|SHELLCHECK_BIN=$c2/home/.local/bin/shellcheck|SHELLCHECK_VERSION=$VERSION|" \
  "$(flatten "$c2/github_env")"
# cleanup: workdir が実在したことを curl.log で確かめた上で、消滅を見る。
check "happy-linux-workdir-recorded" "recorded" "$([ -s "$c2/curl.log" ] && printf 'recorded' || printf 'missing')"
check "happy-linux-workdir-cleaned" "gone" "$(workdir_state "$c2")"

# =========================================================================
# case 3: GITHUB_PATH / GITHUB_ENV 未設定でも落ちず NOTE を出す
# =========================================================================
# 検査対象は `set -u` なので、`${GITHUB_PATH:-}` の既定値が落ちると
# unbound variable で死ぬ。その退行をここで検出する。
c3="$(new_case no-github-vars)"
place_stubs "$c3" uname:uname curl:curl sha256sum:sha256sum tar:tar
rc=0
run_script "$c3" \
  STUB_OS=Linux STUB_ARCH=x86_64 \
  STUB_EXPECT_URL="$(expect_url linux.x86_64)" \
  STUB_SHA_VALUE="$SHA_LINUX" \
  STUB_VERSION="$VERSION" || rc=$?
check "no-github-vars-exit" 0 "$rc"
check_contains "no-github-vars-path-note" "$c3/stdout" "NOTE: GITHUB_PATH is unset"
check_contains "no-github-vars-env-note" "$c3/stdout" "NOTE: GITHUB_ENV is unset"

# =========================================================================
# case 4: sha256sum が無い環境では shasum -a 256 にフォールバックする
# =========================================================================
# shasum スタブが `-a 256` 以外で呼ばれたら exit 91 で落ちるので、
# 引数からアルゴリズム指定が落ちる退行も exit code に現れる。
c4="$(new_case shasum-fallback)"
place_stubs "$c4" uname:uname curl:curl shasum:shasum tar:tar
rc=0
run_script "$c4" \
  STUB_OS=Linux STUB_ARCH=x86_64 \
  STUB_EXPECT_URL="$(expect_url linux.x86_64)" \
  STUB_SHA_VALUE="$SHA_LINUX" \
  STUB_VERSION="$VERSION" || rc=$?
check "shasum-fallback-exit" 0 "$rc"
check "shasum-fallback-installed" "executable" "$(installed_state "$c4")"

# =========================================================================
# case 5: checksum 不一致で exit 1・設置しない・診断に両方の値を出す
# =========================================================================
# このスイートの中核。ここが pass しなくなる = サプライチェーン検証が
# 無効化されている、という対応になる。
c5="$(new_case checksum-mismatch)"
place_stubs "$c5" uname:uname curl:curl sha256sum:sha256sum tar:tar
rc=0
run_script "$c5" \
  STUB_OS=Linux STUB_ARCH=x86_64 \
  STUB_EXPECT_URL="$(expect_url linux.x86_64)" \
  STUB_SHA_VALUE="$WRONG_SHA" \
  STUB_VERSION="$VERSION" || rc=$?
check "checksum-mismatch-exit" 1 "$rc"
check_contains "checksum-mismatch-stderr" "$c5/stderr" "checksum mismatch"
# expected / actual の**値そのもの**を出すことが診断の実用性の核。
check_contains "checksum-mismatch-expected" "$c5/stderr" "$SHA_LINUX"
check_contains "checksum-mismatch-actual" "$c5/stderr" "$WRONG_SHA"
check "checksum-mismatch-not-installed" "absent" "$(installed_state "$c5")"
check "checksum-mismatch-workdir-cleaned" "gone" "$(workdir_state "$c5")"

# =========================================================================
# case 6: curl 失敗で非 0 終了・workdir を残さない
# =========================================================================
c6="$(new_case curl-failure)"
place_stubs "$c6" uname:uname curl:curl sha256sum:sha256sum tar:tar
rc=0
run_script "$c6" \
  STUB_OS=Linux STUB_ARCH=x86_64 \
  STUB_EXPECT_URL="$(expect_url linux.x86_64)" \
  STUB_SHA_VALUE="$SHA_LINUX" \
  STUB_VERSION="$VERSION" \
  STUB_CURL_FAIL=1 || rc=$?
check "curl-failure-exit" 22 "$rc"
check "curl-failure-not-installed" "absent" "$(installed_state "$c6")"
check "curl-failure-workdir-cleaned" "gone" "$(workdir_state "$c6")"

# =========================================================================
# case 7: 展開失敗で非 0 終了・workdir を残さない
# =========================================================================
c7="$(new_case tar-failure)"
place_stubs "$c7" uname:uname curl:curl sha256sum:sha256sum tar:tar-fail
rc=0
run_script "$c7" \
  STUB_OS=Linux STUB_ARCH=x86_64 \
  STUB_EXPECT_URL="$(expect_url linux.x86_64)" \
  STUB_SHA_VALUE="$SHA_LINUX" \
  STUB_VERSION="$VERSION" || rc=$?
check "tar-failure-exit" 1 "$rc"
check "tar-failure-not-installed" "absent" "$(installed_state "$c7")"
check "tar-failure-workdir-cleaned" "gone" "$(workdir_state "$c7")"

# =========================================================================
# case 8: install 失敗で非 0 終了・GITHUB_PATH に追記しない
# =========================================================================
# 「install は失敗したのに PATH には足す」= 後続 step が古い
# pre-install 版を掴んだまま green になる偽 pass の退行を検出する。
c8="$(new_case install-failure)"
place_stubs "$c8" uname:uname curl:curl sha256sum:sha256sum tar:tar install:install-fail
printf '/pre/existing/path\n' >"$c8/github_path"
rc=0
run_script "$c8" \
  STUB_OS=Linux STUB_ARCH=x86_64 \
  STUB_EXPECT_URL="$(expect_url linux.x86_64)" \
  STUB_SHA_VALUE="$SHA_LINUX" \
  STUB_VERSION="$VERSION" \
  GITHUB_PATH="$c8/github_path" || rc=$?
check "install-failure-exit" 1 "$rc"
check "install-failure-not-installed" "absent" "$(installed_state "$c8")"
check "install-failure-no-path-append" "/pre/existing/path|" "$(flatten "$c8/github_path")"
check "install-failure-workdir-cleaned" "gone" "$(workdir_state "$c8")"

# =========================================================================
# case 9: Darwin/arm64 は darwin.aarch64 の asset と Darwin 用 SHA を使う
# =========================================================================
# curl スタブが URL を完全一致で assert し、sha スタブが Darwin 用の値を
# 返すため、platform 表の取り違え (asset 名 / SHA の対応ずれ) は
# exit code に現れる。
c9="$(new_case happy-darwin)"
place_stubs "$c9" uname:uname curl:curl shasum:shasum tar:tar
rc=0
run_script "$c9" \
  STUB_OS=Darwin STUB_ARCH=arm64 \
  STUB_EXPECT_URL="$(expect_url darwin.aarch64)" \
  STUB_SHA_VALUE="$SHA_DARWIN" \
  STUB_VERSION="$VERSION" || rc=$?
check "happy-darwin-exit" 0 "$rc"
check "happy-darwin-installed" "executable" "$(installed_state "$c9")"

# --- 実行数の floor -----------------------------------------------------
# ケースを消しても検出が下がらないよう、期待値は**独立した定数**として
# 持つ (ケース配列の長さ等から導出しない — claude/rules/shell.md)。
# 数えるのは pass 数ではなく実行数 (pass + fail): pass を見ると
# 「実行されたが FAIL した」を「実行されていない」と誤報告する。
# ホスト条件で skip されるケースは無いので差し引きは不要。
EXPECTED_ASSERTS=32
ran=$((pass + fail))
if [ "$ran" -ne "$EXPECTED_ASSERTS" ]; then
  echo "FAIL assert-floor: 実行数が期待と違う (expected=$EXPECTED_ASSERTS ran=$ran)"
  echo "  ケースを増減したら EXPECTED_ASSERTS も更新すること"
  fail=$((fail + 1))
fi

echo "----"
echo "install-shellcheck tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
