#!/usr/bin/env bash
set -euo pipefail

# hook の stdout が JSON に見える形で始まっていないかを検査する横断 linter (issue #240)。
#
# codex は hook の stdout が `{` / `[` で始まると JSON 出力とみなし (`looks_like_json`)、
# パースに失敗した時点で run を Failed にして**本文を model の context に入れない**。
# Claude Code 側は素通しなので、共通の正本 (agents/hooks/) を codex に配線した瞬間に
# 片方の harness でだけ静かに壊れる。実測根拠は docs/ai-operations.md §10。
#
# 検査は fail-closed (違反 1 件で exit 1)。走査対象は hook ディレクトリの**実体のみ**
# (`-type f` なので claude/hooks・codex/hooks の symlink は自然に落ち、二重検査に
# ならない。`make test` の shellcheck が symlink を除外しているのと同じ考え方)。
#
# 判定の粒度と限界:
#   - 静的解析では「どの出力が先頭行になるか」を原理的に決められないため、
#     **stdout に出るリテラルが行位置を問わず `{` / `[` で始まったら違反**とする
#     (over-broad な fail-closed)。誤検知はリテラルの書き換えで安く解消できるが、
#     見逃しは静かに壊れるほうに倒れるため。
#   - 変数展開経由の出力 (`printf '%s\n' "$x"`) は静的には見えない。この穴は
#     hook ごとの実行時 pin (例: tests/session-compact/ の先頭行全文 pin) で塞ぐ。
#   - stderr 送り (`>&2`) の segment は対象外。除外は「その segment に `>&2` が
#     ある場合」だけの狭い側に倒す (`cat <<EOF | tee log` のような stdout にも
#     残る形を誤って許可しないため)。
#   - 意図的に JSON を stdout に出す hook は現在 0 本。必要になった時点で
#     opt-out の形式を設計する (先回りして逃げ道を作らない)。

# リテラルの 1 文字目をバイトで見る。ロケール依存の照合順序を持ち込まない。
export LC_ALL=C

# 走査 root は LINT_HOOK_STDOUT_ROOT で override 可 (テストが scratch fixture root を
# 指すのに使う)。デフォルトは linter 自身のあるリポジトリ root。
scan_root="${LINT_HOOK_STDOUT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

scan_dirs="agents/hooks claude/hooks codex/hooks"

scan_file() {
    awk -v FILE="$1" '
        function is_json_prefix(c) { return (c == "[" || c == "{") }

        # 引用を意識して 1 行をコマンド segment に割る。segment 境界は
        # unquoted な ; | & のみ (リダイレクトは segment 内に残す)。
        # `>&2` / `2>&1` の & は境界にしない — 割ってしまうと `echo x >&2` の
        # segment から `&2` が落ち、stderr 送りを stdout と誤認する。
        function split_segments(line, segs,   i, n, ch, q, cur, cnt) {
            n = length(line); cur = ""; cnt = 0; q = ""
            for (i = 1; i <= n; i++) {
                ch = substr(line, i, 1)
                if (q != "") {
                    if (q == "\"" && ch == "\\") { cur = cur ch substr(line, i + 1, 1); i++; continue }
                    cur = cur ch
                    if (ch == q) q = ""
                    continue
                }
                if (ch == "'"'"'" || ch == "\"") { q = ch; cur = cur ch; continue }
                if (ch == "\\") { cur = cur ch substr(line, i + 1, 1); i++; continue }
                if (ch == "&" && (substr(line, i - 1, 1) == ">" || substr(line, i + 1, 1) == ">")) {
                    cur = cur ch; continue
                }
                if (ch == ";" || ch == "|" || ch == "&") { segs[++cnt] = cur; cur = ""; continue }
                cur = cur ch
            }
            segs[++cnt] = cur
            return cnt
        }

        # echo / printf の引数リテラルを走査し、1 文字目が { / [ のものがあれば 1。
        # printf は第 1 引数がフォーマット文字列なので、**全リテラル引数**を見る
        # (`printf "%s\n" "[x]"` のように 2 個目以降が先頭に立つ形があるため)。
        function bad_literal(seg,   i, n, ch, j) {
            sub(/^[[:space:]]*(echo|printf)[[:space:]]+/, "", seg)
            n = length(seg); i = 1
            while (i <= n) {
                ch = substr(seg, i, 1)
                if (ch == " " || ch == "\t") { i++; continue }
                if (ch == "'"'"'" || ch == "\"") {
                    if (is_json_prefix(substr(seg, i + 1, 1))) return 1
                    j = index(substr(seg, i + 1), ch)
                    if (j == 0) return 0   # 閉じ引用が無い (行継続等) — 判定しない
                    i = i + j + 1
                    continue
                }
                # 裸トークン: 変数展開・リダイレクト・フラグは対象外
                if (is_json_prefix(ch)) return 1
                while (i <= n && substr(seg, i, 1) != " " && substr(seg, i, 1) != "\t") i++
            }
            return 0
        }

        # heredoc 本文の追跡中は、本文行だけを見る (コメント判定より先)
        in_hd {
            line = $0
            if (hd_dash) sub(/^\t+/, "", line)
            if (line == hd_term) { in_hd = 0; next }
            if (!hd_stderr && is_json_prefix(substr($0, 1, 1))) {
                printf "%s:%d: heredoc-json-prefix\n", FILE, NR > "/dev/stderr"
            }
            next
        }

        /^[[:space:]]*#/ { next }

        # heredoc 開始行の検出 (<<< の here-string は語頭が引用符か英字でないため外れる)
        match($0, /<<-?[[:space:]]*("[A-Za-z_][A-Za-z0-9_]*"|'"'"'[A-Za-z_][A-Za-z0-9_]*'"'"'|[A-Za-z_][A-Za-z0-9_]*)/) {
            tok = substr($0, RSTART, RLENGTH)
            hd_dash = (substr(tok, 3, 1) == "-")
            sub(/^<<-?[[:space:]]*/, "", tok)
            gsub(/["'"'"']/, "", tok)
            hd_term = tok
            hd_stderr = ($0 ~ />&2/)
            in_hd = 1
            next
        }

        {
            cnt = split_segments($0, segs)
            for (s = 1; s <= cnt; s++) {
                if (segs[s] !~ /^[[:space:]]*(echo|printf)[[:space:]]/) continue
                if (segs[s] ~ />&2/) continue
                if (bad_literal(segs[s])) {
                    printf "%s:%d: stdout-json-prefix\n", FILE, NR > "/dev/stderr"
                    break
                }
            }
            delete segs
        }
    ' "$1"
}

violations=""
for d in $scan_dirs; do
    [ -d "${scan_root}/${d}" ] || continue
    while IFS= read -r f; do
        out=$(scan_file "${scan_root}/${f}" 2>&1 >/dev/null)
        [ -n "$out" ] && violations="${violations}${out}"$'\n'
    done < <(cd "$scan_root" && find "$d" -type f -name '*.sh' | sort)
done

if [ -n "$violations" ]; then
    {
        echo "hook stdout が JSON に見える形で始まっています (codex では本文が捨てられます):"
        printf '%s' "$violations"
        echo "対処: そのリテラルの先頭から { / [ を外すか、出力を stderr (>&2) に回す"
    } >&2
    exit 1
fi
exit 0
