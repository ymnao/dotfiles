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
# bash 3.2 で回るため (B) 系の検出網が保たれる。CI (Linux ubuntu / bash 5) では
# 原理的に (B) 系は再現しないが、(A) 系は matrix で検出できる。macOS runner
# (bash 3.2 CI 化) は別 issue で単独評価する。
#
# 実行しないロケールが host に無い場合は WARN + skip し、全体の exit code は
# 「実行された分に fail が 1 つでもあれば非 0」で決める。

LOCALES="C en_US.UTF-8 ja_JP.UTF-8"

available_locales=$(locale -a 2>/dev/null || true)

# エイリアスの吸収 (例: locale -a が "en_US.utf8" と返す環境がある)。
# 大文字小文字と "-" 有無を無視して includes 判定する。
locale_available() {
    local target="$1"
    local normalized_target
    normalized_target=$(printf '%s' "$target" | tr 'A-Z' 'a-z' | tr -d '-')
    local line
    while IFS= read -r line; do
        local normalized
        normalized=$(printf '%s' "$line" | tr 'A-Z' 'a-z' | tr -d '-')
        if [ "$normalized" = "$normalized_target" ]; then
            return 0
        fi
    done <<EOF
$available_locales
EOF
    return 1
}

overall_status=0
ran=""
skipped=""
failed=""

for loc in $LOCALES; do
    printf '\n===== locale=%s bash=%s =====\n' "$loc" "$BASH_VERSION"
    if ! locale_available "$loc"; then
        printf 'WARN: locale "%s" not available on this host, skipping.\n' "$loc" >&2
        skipped="${skipped}${loc} "
        continue
    fi
    ran="${ran}${loc} "
    if env LC_ALL="$loc" LANG="$loc" make test; then
        printf 'PASS locale=%s\n' "$loc"
    else
        rc=$?
        printf 'FAIL locale=%s (exit=%d)\n' "$loc" "$rc" >&2
        failed="${failed}${loc} "
        overall_status=1
    fi
done

printf '\n===== summary =====\n'
printf 'ran:     %s\n' "${ran:-<none>}"
printf 'skipped: %s\n' "${skipped:-<none>}"
printf 'failed:  %s\n' "${failed:-<none>}"

if [ -z "$ran" ]; then
    printf 'ERROR: no locale in "%s" was available on this host.\n' "$LOCALES" >&2
    exit 1
fi

exit "$overall_status"
