#!/usr/bin/env bash
set -euo pipefail

# LC_ALL pin 忘れの静的 linter (issue #192)。
# scripts/ tests/ 配下の *.sh を走査し、ロケール依存構文を含む行のうち
# shebang 直下の `export LC_ALL=` (ファイル全体 pin) と行内 `LC_ALL=`
# prefix (行スコープ pin) のどちらも無いものを warning として stderr に
# 出力する。exit code は常に 0 (warning-only)。issue #181 の LC_ALL
# matrix が silent-wrong パスや matrix 外 locale (ja_JP.SJIS 等) を
# 拾えないための補助チェック。詳細は claude/rules/shell.md 参照。

# 自分自身をバイト単位で処理する (多バイト検出とファイル探索の順序を
# ambient locale に依存させない)。
export LC_ALL=C

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
self_path="${repo_root}/scripts/lint-locale-pin.sh"

scan_file() {
    local f="$1"
    # ファイル全体 pin: 先頭 20 行以内に `export LC_ALL=` があれば skip。
    # shebang + 数行のコメント + set -euo pipefail + export LC_ALL= を
    # 想定した余裕値。実例 (tests/agents-md-sync/run-agents-md-sync-check.sh)
    # では 9 行目に配置されている。
    if head -n 20 "$f" | grep -qE '^[[:space:]]*export[[:space:]]+LC_ALL='; then
        return 0
    fi

    # 行単位判定は awk 1 pass。コメント行と行内 LC_ALL= を除外し 3 パターンを評価。
    # regex は POSIX ERE のみ (BSD awk 前提)。
    # 1) awk-equals: BSD awk の == は strcoll() 依存 (issue #181 地雷 A)。
    # 2) multibyte: 「非 ASCII バイトを比較コンテキストで使う」行だけ拾う
    #    (grep/awk/[[/=~ を含む行に限定)。echo/printf/heredoc/エラーメッセージ
    #    への日本語混在は FP なので除外。多バイト検出は [^\t -~] complement。
    # 3) sort: 識別子境界一致。ロケール依存の照合順序を踏む可能性。
    awk -v FILE="$f" '
        /^[[:space:]]*#/ { next }
        /LC_ALL=/ { next }
        /awk/ && /==/ { printf "%s:%d: awk-equals\n", FILE, NR > "/dev/stderr"; next }
        /[^\t -~]/ && (/grep/ || /awk/ || /\[\[/ || /=~/) { printf "%s:%d: multibyte\n", FILE, NR > "/dev/stderr"; next }
        /(^|[^A-Za-z0-9_-])sort([^A-Za-z0-9_-]|$)/ { printf "%s:%d: sort\n", FILE, NR > "/dev/stderr"; next }
    ' "$f"
}

# find の並び順を LC_ALL=C sort で再現性を持たせる (出力順は診断性のため)。
while IFS= read -r rel; do
    abs="${repo_root}/${rel}"
    # 自分自身は除外 (linter 内の awk == / sort パターン記述が自己ヒットするため)
    [ "$abs" = "$self_path" ] && continue
    scan_file "$abs"
done < <(cd "$repo_root" && find scripts tests -type f -name '*.sh' | sort)
