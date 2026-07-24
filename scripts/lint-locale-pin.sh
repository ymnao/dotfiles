#!/usr/bin/env bash
set -euo pipefail

# LC_ALL pin 忘れの静的 linter (issue #192)。
# scripts/ tests/ 配下の *.sh を走査し、ロケール依存構文を含む行を stderr に
# warning 出力する。exit code は常に 0 (warning-only)。issue #181 の LC_ALL
# matrix が silent-wrong パスや matrix 外 locale (ja_JP.SJIS 等) を拾えない
# ための補助チェック。詳細は claude/rules/shell.md 参照。
#
# 判定は awk 単一 pass。以下の順で評価:
#   1) `export LC_ALL=` に到達 → 以降そのファイル内はすべて skip (全体 pin)
#   2) 行内 `LC_ALL=` prefix → その行 skip (行スコープ pin)
#   3) コメント行 → skip
#   4) `awk` かつ `==` を含む → awk-equals (BSD awk の == は strcoll 依存)
#   5) 非 ASCII バイト × 比較 context (grep/awk/[[/=~) → multibyte
#      (test/[/case への拡張は run-gate:86 等の "make test" 文字列で FP を
#      増やすだけで case 文の実 pattern (別行) は捉えられないため見送り)
#   6) `sort` 単語一致 → sort (ロケール依存の照合順序)

export LC_ALL=C

# 走査対象は LINT_LOCALE_PIN_ROOT で override 可 (テストが scratch fixture root
# を指すのに使う)。デフォルトは linter 自身のあるリポジトリ root。
scan_root="${LINT_LOCALE_PIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
self_path="${scan_root}/scripts/lint-locale-pin.sh"

scan_file() {
    local f="$1"
    awk -v FILE="$f" '
        /^[[:space:]]*export[[:space:]]+LC_ALL=/ { pinned = 1; next }
        pinned { next }
        /LC_ALL=/ { next }
        /^[[:space:]]*#/ { next }
        /awk/ && /==/ { printf "%s:%d: awk-equals\n", FILE, NR > "/dev/stderr"; next }
        /[^\t -~]/ && (/grep/ || /awk/ || /\[\[/ || /=~/) {
            printf "%s:%d: multibyte\n", FILE, NR > "/dev/stderr"; next
        }
        /(^|[^A-Za-z0-9_-])sort([^A-Za-z0-9_-]|$)/ { printf "%s:%d: sort\n", FILE, NR > "/dev/stderr"; next }
    ' "$f"
}

while IFS= read -r rel; do
    abs="${scan_root}/${rel}"
    # 自分自身は除外 (linter 内の awk == / sort パターン記述が自己ヒットするため)
    [ "$abs" = "$self_path" ] && continue
    scan_file "$abs"
done < <(cd "$scan_root" && find scripts tests -type f -name '*.sh' | sort)
