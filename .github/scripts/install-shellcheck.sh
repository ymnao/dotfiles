#!/usr/bin/env bash
# CI 用 shellcheck インストーラ (issue #196)。配置先: .github/scripts/install-shellcheck.sh
#
# 目的: CI が使う shellcheck のバージョンを run 間で固定し、apt / Homebrew の
# 可用性とバージョン方針から CI を切り離す。
#
# なぜパッケージマネージャをやめたか:
#   - ubuntu-24.04 runner には shellcheck 0.9.0 が pre-install 済みで、開発機
#     (Homebrew 最新 = 0.11.0) より **緩い**。`make test` は全 *.sh に
#     `shellcheck -S warning` を掛けるため、この乖離は「手元で出る指摘が CI では
#     出ない」方向の実害になっていた
#   - macos runner には shellcheck が pre-install されておらず、`brew install` が
#     毎回ネットワークから最新版を取得していた (同じコミットでも結果が変わりうる)
#   - `apt-get update` / `brew install` はレジストリ側の障害でそのまま CI の
#     偶発 fail になる
#
# なぜ GitHub Releases の直取得か:
#   - homebrew-core に shellcheck の versioned formula は存在しない
#     (`brew search /^shellcheck/` → `shellcheck` のみ)
#   - apt 側の `shellcheck=0.9.0-1` 形式の pin は Ubuntu が旧版を保持しないため
#     runner イメージ更新で壊れる
#   - 依存する外部サービスは GitHub 1 社に閉じる (checkout と同じ)。ただし
#     release asset の実体は `release-assets.githubusercontent.com` へ
#     リダイレクトされる (2026-07-28 に Location ヘッダで実測) ので、
#     **checkout とは別ドメインが 1 つ増える**点は正確に把握しておく
#
# jq を扱わない理由: CI での用途が `jq empty` 等の構文検証のみでバージョン感度が
# 無く、SHA 管理コストが価値を上回る。runner pre-install を workflow 側の assert
# 付きで使う (pre-install が消えたら assert が明示 fail する)。将来 jq の
# バージョン依存問題が実際に出たら、この構造のまま jq を足せる。
#
# バージョンを上げる手順:
#   1. 下の VERSION と 2 つの SHA256 を更新する (SHA256 は
#      `gh release download <tag> --repo koalaman/shellcheck --pattern '...'` +
#      `shasum -a 256` で実測する。README 等の転記はしない)
#   2. **先に手元で `make test` を通す**。Brewfile の shellcheck は unpin なので
#      開発機は Homebrew 追従で先行しやすく、その間は開発機の方が厳しい側に
#      倒れる (新バージョンの新規 warning が手元で先に出る)。ただしこれは
#      2026-07-28 時点 (dev 0.11.0 / この pin 0.11.0) の状態であって不変では
#      ない。Homebrew が先に上がれば CI が緩い側に転ぶので、bump を溜めない。
#   Dependabot は GitHub Releases の直取得を追跡しないため bump は手動運用。
#   放置したときの比較は経路で違う: Linux は置き換え前が runner イメージ同梱の
#   0.9.0 固定だったので悪化しない。**macOS は置き換え前が brew 最新追従だった
#   ので、放置すればそちらより古くなる**。macOS 側は weekly 実行で目に付き
#   にくい分、bump を溜めない理由がここにもある。
#
# 制約: **bash 3.2 互換**で書く (連想配列を使わない)。根拠は macOS 標準 bash に
# 合わせる repo 全体の規約 (claude/rules/shell.md)。
# 実行系の対応関係を正確に書いておく:
#   - workflow は `bash <path>` で起動するので **shebang は参照されない**。
#     どの bash で走るかは PATH 上の `bash` の解決結果で決まる
#   - macOS runner (macos-15-arm64 / macos-26-arm64) のイメージに含まれる bash は
#     `Bash 3.2.57(1)-release` のみで、Homebrew の bash 5.x は入っていない
#     (2026-07-28 に actions/runner-images の README を取得して確認)。
#     つまり macOS 側ではこのスクリプトは実際に bash 3.2 で走る
#   - test-macos.yml の `defaults.run.shell` による pin は step 直下の shell に
#     しか効かないので、そこは根拠にならない (同 workflow が自ら注記している)
# `scripts/lib/log.sh` は source しない — CI 専用で repo 内の他スクリプトから
# 独立させ、checkout レイアウトへの依存を作らないため。
set -euo pipefail

# ロケール依存の出力ゆらぎを排除する (claude/rules/shell.md)。
# 注: `make lint-locale-pin` の走査対象は scripts/ と tests/ のみで .github/ は
# 対象外だが、規約自体はこのファイルにも適用する。
export LC_ALL=C

VERSION="v0.11.0"
SHA256_LINUX_X86_64="8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198"
SHA256_DARWIN_AARCH64="56affdd8de5527894dca6dc3d7e0a99a873b0f004d7aabc30ae407d3f48b0a79"

# 対応するのは現行 runner の 2 経路のみ。未知の platform を暗黙に素通りさせると
# 「pre-install の別バージョンが使われて green」という偽 pass になるため明示 fail
# する (ubuntu-latest が arm に移る等の変化は SHA 追加で対応する)。
os="$(uname -s)"
arch="$(uname -m)"
case "${os}/${arch}" in
    Linux/x86_64)
        platform="linux.x86_64"
        expected_sha="$SHA256_LINUX_X86_64"
        ;;
    Darwin/arm64)
        platform="darwin.aarch64"
        expected_sha="$SHA256_DARWIN_AARCH64"
        ;;
    *)
        printf 'ERROR: unsupported platform: %s/%s\n' "$os" "$arch" >&2
        printf 'Add the corresponding SHA256 to %s to support it.\n' "$0" >&2
        exit 1
        ;;
esac

archive="shellcheck-${VERSION}.${platform}.tar.xz"
url="https://github.com/koalaman/shellcheck/releases/download/${VERSION}/${archive}"
dest_dir="${HOME}/.local/bin"

# テンプレートを明示する: macOS の BSD mktemp はテンプレート無しだと TMPDIR を
# 無視して confstr の per-user temp dir を使うため、TMPDIR を差し替えた環境
# (サンドボックス下の手元検証等) で作業先が意図とずれる。
workdir="$(mktemp -d "${TMPDIR:-/tmp}/shellcheck-install.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

printf '==> downloading %s\n' "$url"
# --retry は一時的な瞬断のみを吸収する目的で、恒常障害を粘る意図は無い。
# --retry 単体の対象は timeout と 408/429/5xx 等で、ECONNREFUSED は入らない
# ため --retry-connrefused を併用する。**DNS 解決失敗は依然として再試行されない**
# (拾うには --retry-all-errors が要る)。取りこぼす範囲を承知の上で、
# 「どんなエラーでも 3 回粘る」より失敗を早く見せる側を選んでいる。
curl -fsSL --retry 3 --retry-delay 2 --retry-connrefused -o "${workdir}/${archive}" "$url"

# SHA256 検証。Linux は sha256sum、macOS は shasum -a 256 (coreutils 非前提)。
if command -v sha256sum >/dev/null 2>&1; then
    actual_sha="$(sha256sum "${workdir}/${archive}" | cut -d' ' -f1)"
else
    actual_sha="$(shasum -a 256 "${workdir}/${archive}" | cut -d' ' -f1)"
fi

if [ "$actual_sha" != "$expected_sha" ]; then
    printf 'ERROR: checksum mismatch for %s\n' "$archive" >&2
    printf '  expected: %s\n' "$expected_sha" >&2
    printf '  actual:   %s\n' "$actual_sha" >&2
    exit 1
fi
printf '==> checksum OK (%s)\n' "$expected_sha"

tar -xJf "${workdir}/${archive}" -C "$workdir"
mkdir -p "$dest_dir"
install -m 0755 "${workdir}/shellcheck-${VERSION}/shellcheck" "${dest_dir}/shellcheck"

# GITHUB_PATH への追記は後続 step の PATH 先頭側に入るため、runner
# pre-install の /usr/bin/shellcheck (0.9.0) より優先される。実際にどちらが
# 解決されるかは workflow 側の assert で検証する (ここでの追記だけを信用しない)。
#
# 設置先とバージョンは SHELLCHECK_BIN / SHELLCHECK_VERSION として GITHUB_ENV
# 経由で後続 step に渡す。workflow 側に path やバージョン番号をリテラルで転記
# すると正本が複数箇所に分かれ、片方を変えたときに assert が追従せず
# 「install は成功、しかし解決されているのは pin ではない」という、この変更が
# 防ごうとしているのと同型の偽 pass を招くため。
#
# path だけでなくバージョンも渡すのは、path 一致は「自分が GITHUB_PATH に足した
# ディレクトリが PATH 競争に勝ったか」しか見ておらず、その実体が pin 版である
# 保証にならないため (両方 assert して初めて目的を閉じられる)。
if [ -n "${GITHUB_PATH:-}" ]; then
    printf '%s\n' "$dest_dir" >> "$GITHUB_PATH"
else
    printf 'NOTE: GITHUB_PATH is unset; add %s to PATH manually\n' "$dest_dir"
fi

if [ -n "${GITHUB_ENV:-}" ]; then
    printf 'SHELLCHECK_BIN=%s\n' "${dest_dir}/shellcheck" >> "$GITHUB_ENV"
    printf 'SHELLCHECK_VERSION=%s\n' "$VERSION" >> "$GITHUB_ENV"
else
    printf 'NOTE: GITHUB_ENV is unset; SHELLCHECK_BIN / SHELLCHECK_VERSION not exported\n'
fi

printf '==> installed to %s\n' "${dest_dir}/shellcheck"
"${dest_dir}/shellcheck" --version
