#!/usr/bin/env bash
set -uo pipefail

# ロケール軸再発防止 driver (issue #181)。
#
# 過去に踏んだ地雷:
#   (A) tests/agents-md-sync — BSD awk の == が strcoll() 依存で
#       LC_ALL=en_US.UTF-8 では日本語文字列が誤 equal になる
#       (現在は run-agents-md-sync-check.sh 冒頭で LC_ALL=C を pin)
#   (B) agents/hooks/verify-ci-before-pr.sh — bash 3.2 + UTF-8 ロケールで
#       heredoc 内の "$VAR」" (多バイト文字直後の変数展開) が unbound で即死
#       (現在は ${VAR} 明示 + run-verify-ci-tests.sh:252 の UTF-8 回帰ケース)
#
# Makefile 全体の LC_ALL=C 固定は却下確定 (デフォルト en_US.UTF-8 で make test
# を回したから (B) を検出できた、全体固定するとこの class を永久にすり抜ける)。
# 代わりに: ロケールを明示的に振って make test を回す。
#
# bash 版数は「現在の bash」(呼び出し元 shell) をそのまま使う。macOS 手元では
# bash 3.2 で回るため (B) 系の検出網が「実行された時だけ」機能する (常時強制で
# はない、開発者が手元で叩いた時のみ)。CI (Linux ubuntu / bash 5) では原理的に
# (B) 系は再現しないが、(A) 系は matrix で検出できる。macOS runner (bash 3.2
# CI 化) は本 issue のフォローアップとして別 issue で単独評価する。
#
# 実行しないロケールが host に無い場合は WARN + skip し、全体の exit code は
# 「実行された分に fail が 1 つでもあれば非 0」で決める。

LOCALES="C en_US.UTF-8 ja_JP.UTF-8"

# エイリアス (例: locale -a が "en_US.utf8" と返す環境) を吸収するため、
# 事前に available_locales を「小文字化 + ハイフン除去」で正規化しておく。
# 以降の locale_available は grep -qx で 1 回だけ突き合わせる (O(N) 1 パス)。
available_locales_normalized=$(
    locale -a 2>/dev/null | tr 'A-Z' 'a-z' | tr -d '-' || true
)

locale_available() {
    local normalized
    normalized=$(printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -d '-')
    printf '%s\n' "$available_locales_normalized" | grep -qx "$normalized"
}

# ran/skipped/failed は indexed array で持つ (bash 3.2 で使用可能な範囲)。
# 空判定は要素数、表示は "${arr[*]}" で結合、成否は failed の要素数で導出する。
ran=()
skipped=()
failed=()

for loc in $LOCALES; do
    printf '\n===== locale=%s bash=%s =====\n' "$loc" "$BASH_VERSION"
    if ! locale_available "$loc"; then
        printf 'WARN: locale "%s" not available on this host, skipping.\n' "$loc" >&2
        skipped+=("$loc")
        continue
    fi
    ran+=("$loc")
    if env LC_ALL="$loc" LANG="$loc" make test; then
        printf 'PASS locale=%s\n' "$loc"
    else
        rc=$?
        printf 'FAIL locale=%s (exit=%d)\n' "$loc" "$rc" >&2
        failed+=("$loc")
    fi
done

# ${arr[*]:-} 形式は bash 3.2 + set -u で空配列参照が unbound になるのを避ける。
printf '\n===== summary =====\n'
printf 'ran:     %s\n' "${ran[*]:-<none>}"
printf 'skipped: %s\n' "${skipped[*]:-<none>}"
printf 'failed:  %s\n' "${failed[*]:-<none>}"

if [ ${#ran[@]} -eq 0 ]; then
    printf 'ERROR: no locale in "%s" was available on this host.\n' "$LOCALES" >&2
    exit 1
fi

if [ ${#failed[@]} -gt 0 ]; then
    exit 1
fi
exit 0
