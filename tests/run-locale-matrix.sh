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

LOCALES=(C en_US.UTF-8 ja_JP.UTF-8)

# エイリアス (例: locale -a が "en_US.utf8" と返す環境) を吸収するため、
# 事前に available_locales を「小文字化 + ハイフン除去」で正規化しておく。
# 以降の locale_available は grep -qx で 1 回だけ突き合わせる (O(N) 1 パス)。
# tr の class 指定は敢えて `A-Z / a-z` (ASCII 範囲リテラル) にする。
# `[:upper:]/[:lower:]` は tr 実装によって ambient LC_CTYPE の影響を受け、
# ロケール判定用の正規化として振る舞いがブレる。shellcheck SC2018/SC2019 の
# info は本用途では意図的に無視する。
# さらに tr の range 解釈自体も一部実装で ambient LC_COLLATE に依存するため、
# `LC_ALL=C tr` で ASCII バイト範囲を明示的に固定する。
available_locales_normalized=$(
    locale -a 2>/dev/null | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C tr -d '-' || true
)

locale_available() {
    local normalized
    normalized=$(printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C tr -d '-')
    # grep -F で fixed-string マッチ。正規化後のロケール名 (en_us.utf8 等) に
    # 含まれる `.` を正規表現の任意 1 文字として解釈させないため。
    printf '%s\n' "$available_locales_normalized" | grep -Fqx -- "$normalized"
}

# ran/skipped/failed は indexed array で持つ (bash 3.2 で使用可能な範囲)。
# 空判定は要素数、表示は "${arr[*]}" で結合、成否は failed の要素数で導出する。
ran=()
skipped=()
failed=()

for loc in "${LOCALES[@]}"; do
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
    printf 'ERROR: no locale in "%s" was available on this host.\n' "${LOCALES[*]}" >&2
    exit 1
fi

# 過去障害 (A)(B) は UTF-8 ロケール環境で顕在化する。UTF-8 系ロケールが LOCALES
# に含まれているのに host で 1 つも走らなかった場合、「無事故に見えて実は UTF-8
# パスを 1 度も検査していない」状態になり誤った安心を与える (例: C しか無い
# minimal な環境で C 単独 PASS した結果を信頼してしまう)。fail 扱いにする。
# LOCALES から意図的に UTF-8 を外した場合はこの分岐に入らない。
utf8_requested=0
for loc in "${LOCALES[@]}"; do
    case "$loc" in
        *[Uu][Tt][Ff]*) utf8_requested=1; break ;;
    esac
done
if [ "$utf8_requested" = 1 ]; then
    utf8_ran=0
    for loc in "${ran[@]}"; do
        case "$loc" in
            *[Uu][Tt][Ff]*) utf8_ran=1; break ;;
        esac
    done
    if [ "$utf8_ran" = 0 ]; then
        printf 'ERROR: no UTF-8 locale in "%s" was available on this host; UTF-8 系回帰検査 (issue #181) が素通りするため fail 扱い。\n' "${LOCALES[*]}" >&2
        exit 1
    fi
fi

if [ ${#failed[@]} -gt 0 ]; then
    exit 1
fi
exit 0
