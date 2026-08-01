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
# 解析の骨格:
#   1. 行継続 (`\` 末尾) を連結してから 1 論理行として扱う
#   2. **マスク行**を作る — 引用の中身を \001 に潰し、未引用の `#` 以降を捨てた
#      「コードの骨格」。`<<` の検出・`>&2` の判定・segment 分割はすべてこのマスク側で
#      行い、リテラル本文だけを元の行から取る。文字列やコメントの中の `<<` / `>&2` に
#      誤爆すると、**そのファイルの残り全部が無検査になる**ため (検査が静かに消える)
#   3. segment に割り (unquoted な ; | & ( ) { } / `$(` `${` の内側は割らない)、
#      `echo` / `printf` で始まる segment のリテラル引数を調べる
#
# 判定の粒度と限界:
#   - 静的解析では「どの出力が先頭行になるか」を原理的に決められないため、
#     **stdout に出るリテラルが行位置を問わず `{` / `[` で始まったら違反**とする
#     (over-broad な fail-closed)。誤検知はリテラルの書き換えで安く解消できるが、
#     見逃しは静かに壊れるほうに倒れるため。
#   - 先頭の空白と `\n` / `\t` / `\r` エスケープは剥がしてから 1 文字目を見る。
#     codex 側が見るのは実際の出力バイトなので、`printf '\n{...}'` は `{` 始まり
#     ではないが `\n` の**次**が `{` で、改行を挟んで JSON に見える形が残る
#     (issue #215 が「先頭空行 + `{`」の mutant で踏んだ形と同じ)。
#   - 変数展開経由の出力 (`printf '%s\n' "$x"`) は静的には見えない。この穴は
#     hook ごとの実行時 pin (tests/session-compact/ と tests/hooks-integrity/ の
#     先頭行全文 pin) で塞ぐ。
#   - `>&2` の segment は対象外。リダイレクト先がファイルの場合 (`echo '{}' > x.json`)
#     は現状 stdout 扱いで誤検知する。実例が 0 本なので、判定を緩める代わりに
#     踏んだ時点で opt-out の形式を設計する (先回りして逃げ道を作らない)。
#   - 1 行に複数の heredoc を開く形は追跡しない (repo 内に実例なし)。

# リテラルの 1 文字目をバイトで見る。ロケール依存の照合順序を持ち込まない。
export LC_ALL=C

# 走査 root は LINT_HOOK_STDOUT_ROOT で override 可 (テストが scratch fixture root を
# 指すのに使う)。デフォルトは linter 自身のあるリポジトリ root。
scan_root="${LINT_HOOK_STDOUT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

scan_dirs="agents/hooks claude/hooks codex/hooks"

# 走査は awk 1 プロセスに全ファイルを渡して行う (ファイルごとに fork しない)。
# ファイル境界では heredoc 追跡状態を必ずリセットする — 前のファイルが heredoc を
# 閉じずに終わると、次のファイル全体が本文とみなされて検査が丸ごと抜ける。
scan_files() {
    awk '
        function is_json_prefix(s,   c) {
            # 先頭の空白と \n / \t / \r エスケープを剥がしてから 1 文字目を見る
            sub(/^([[:space:]]|\\[nrt])+/, "", s)
            c = substr(s, 1, 1)
            return (c == "[" || c == "{")
        }

        # 引用の中身を \001 に潰し、未引用の行末コメントを捨てたマスク行を返す。
        # 添字は元の行と 1 対 1 で対応する (コメント以降が短くなるだけ)。
        function mask(line,   i, n, ch, q, out) {
            n = length(line); q = ""; out = ""
            for (i = 1; i <= n; i++) {
                ch = substr(line, i, 1)
                if (q != "") {
                    if (q == "\"" && ch == "\\") { out = out "\001\001"; i++; continue }
                    if (ch == q) { out = out ch; q = ""; continue }
                    out = out "\001"; continue
                }
                if (ch == "\\") { out = out ch "\001"; i++; continue }
                if (ch == "'"'"'" || ch == "\"") { q = ch; out = out ch; continue }
                if (ch == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[[:space:]]/)) break
                out = out ch
            }
            return out
        }

        # マスク行を見て segment 境界 (unquoted な ; | & ( ) { }) の添字を segs に積む。
        # `>&2` / `2>&1` の & と、`$(...)` / `${...}` の内側では割らない。
        function split_points(m, segs,   i, n, ch, prev, depth, cnt) {
            n = length(m); cnt = 0; depth = 0
            segs[++cnt] = 1
            for (i = 1; i <= n; i++) {
                ch = substr(m, i, 1)
                prev = (i > 1) ? substr(m, i - 1, 1) : ""
                if (ch == "(" || ch == "{") {
                    if (prev == "$") { depth++; continue }
                    segs[++cnt] = i + 1; continue
                }
                if (ch == ")" || ch == "}") {
                    if (depth > 0) { depth--; continue }
                    segs[++cnt] = i + 1; continue
                }
                if (ch == "&" && (prev == ">" || substr(m, i + 1, 1) == ">")) continue
                if (ch == ";" || ch == "|" || ch == "&") segs[++cnt] = i + 1
            }
            segs[++cnt] = n + 2   # 番兵 (最後の segment の終端計算用)
            return cnt
        }

        # segment 内の echo / printf のリテラル引数を調べる。JSON 始まりがあれば 1。
        # printf は第 1 引数がフォーマット文字列なので**全リテラル引数**を見る
        # (`printf "%s\n" "[x]"` のように 2 個目以降が先頭に立つ形があるため)。
        function bad_literal(txt, m, from,   i, n, ch, j, lit) {
            n = length(m); i = from
            while (i <= n) {
                ch = substr(m, i, 1)
                if (ch == " " || ch == "\t") { i++; continue }
                if (ch == "'"'"'" || ch == "\"") {
                    j = index(substr(m, i + 1), ch)
                    if (j == 0) return 0   # 閉じ引用が無い — 判定しない
                    lit = substr(txt, i + 1, j - 1)
                    if (is_json_prefix(lit)) return 1
                    i = i + j + 1
                    continue
                }
                # 裸トークン (変数展開・リダイレクト・フラグはここで自然に外れる)
                if (is_json_prefix(substr(txt, i))) return 1
                while (i <= n && substr(m, i, 1) != " " && substr(m, i, 1) != "\t") i++
            }
            return 0
        }

        # heredoc 開始を検出したら term / dash / stderr を設定して 1 を返す。
        # `<<<` (here-string) と、引用やコメントの中の `<<` は mask 側で外れる。
        function heredoc_start(line, m,   p, rest, k, ch, term) {
            p = index(m, "<<")
            if (p == 0) return 0
            if (substr(m, p + 2, 1) == "<") return 0
            rest = substr(line, p)
            k = 3
            hd_dash = 0
            if (substr(rest, k, 1) == "-") { hd_dash = 1; k++ }
            while (substr(rest, k, 1) == " " || substr(rest, k, 1) == "\t") k++
            if (substr(rest, k, 1) == "\\") k++      # <<\EOF (展開抑止形)
            ch = substr(rest, k, 1)
            term = ""
            if (ch == "'"'"'" || ch == "\"") {
                k++
                while (k <= length(rest) && substr(rest, k, 1) != ch) { term = term substr(rest, k, 1); k++ }
            } else {
                while (k <= length(rest) && substr(rest, k, 1) ~ /[A-Za-z0-9_]/) { term = term substr(rest, k, 1); k++ }
            }
            if (term == "") return 0
            hd_term = term
            hd_stderr = (m ~ />&2/)
            return 1
        }

        FNR == 1 { in_hd = 0 }

        {
            if (in_hd) {
                body = $0
                if (hd_dash) sub(/^\t+/, "", body)
                if (body == hd_term) { in_hd = 0; next }
                # タブを剥がした後の本文で判定する (剥がす前の $0 を見ると
                # <<- のタブインデント本文が丸ごと素通りする)
                if (!hd_stderr && is_json_prefix(body)) {
                    printf "%s:%d: heredoc-json-prefix\n", FILENAME, FNR > "/dev/stderr"
                }
                next
            }

            line = $0
            ln = FNR
            while (line ~ /\\$/) {          # 行継続を 1 論理行に連結する
                sub(/\\$/, "", line)
                if ((getline nxt) <= 0) break
                line = line nxt
            }
            m = mask(line)
            if (m ~ /^[[:space:]]*$/) next

            if (heredoc_start(line, m)) { in_hd = 1; next }

            cnt = split_points(m, segs)
            for (s = 1; s < cnt; s++) {
                start = segs[s]
                len = segs[s + 1] - start - 1
                if (len <= 0) continue
                seg_m = substr(m, start, len)
                if (seg_m ~ />&2/) continue
                # 制御構文の直後に続く echo / printf も対象にする
                # (`then echo ...` / `do echo ...`。( ) { } と ; | & は segment 境界)
                if (seg_m !~ /^[[:space:]]*((then|else|elif|do)[[:space:]]+)*(echo|printf)[[:space:]]/) continue
                if (!match(seg_m, /(echo|printf)[[:space:]]/)) continue
                if (bad_literal(substr(line, start, len), seg_m, RSTART + RLENGTH)) {
                    printf "%s:%d: stdout-json-prefix\n", FILENAME, ln > "/dev/stderr"
                    break
                }
            }
            delete segs
        }
    ' "$@"
}

# 存在するディレクトリだけを find に渡す (無いディレクトリを渡すと find が
# エラーで非 0 を返す)。
existing_dirs=()
for d in $scan_dirs; do
    if [ -d "${scan_root}/${d}" ]; then
        existing_dirs+=("$d")
    fi
done

files=()
if [ "${#existing_dirs[@]}" -gt 0 ]; then
    while IFS= read -r f; do
        files+=("$f")
    done < <(cd "$scan_root" && find "${existing_dirs[@]}" -type f -name '*.sh' | sort)
fi

# 走査 0 件は「ゲートが静かに消えた」状態 (ディレクトリ改名・root の指定ミス)。
# 緑で通すと検査が無くなったことに気付けないので fail させる。
if [ "${#files[@]}" -eq 0 ]; then
    echo "lint-hook-stdout: 走査対象が 0 件です (root=${scan_root}, dirs=${scan_dirs})" >&2
    echo "hook ディレクトリの改名か root の指定ミスを疑ってください" >&2
    exit 1
fi

# 違反は awk が stderr に出す。stdout 側は捨てて stderr だけを受け取る。
# awk 自体が失敗した場合 (読めないファイル等) も同じ経路に出るため、
# rc を見て診断ごと表示する (代入を素通りさせると何も表示されずに落ちる)。
set +e
violations=$(cd "$scan_root" && scan_files "${files[@]}" 2>&1 >/dev/null)
awk_rc=$?
set -e

if [ "$awk_rc" -ne 0 ]; then
    echo "lint-hook-stdout: 走査に失敗しました (awk rc=${awk_rc})" >&2
    [ -n "$violations" ] && printf '%s\n' "$violations" >&2
    exit 1
fi

if [ -n "$violations" ]; then
    {
        echo "hook stdout が JSON に見える形で始まっています (codex では本文が捨てられます):"
        printf '%s\n' "$violations"
        echo "対処: そのリテラルの先頭から { / [ を外すか、出力を stderr (>&2) に回す"
    } >&2
    exit 1
fi
exit 0
