#!/usr/bin/env bash
set -euo pipefail

# html-brief の renderer (claude/skills/html-brief/render.mjs) の回帰テスト。
#
# 何を守るためのテストか (予防的な網羅ではなく、実際に壊れる経路):
#   - **エスケープ**: 入力の意味データがそのまま HTML に流れると生成物が壊れる
#     (agent が書く文字列に <, &, ", ' が混ざるのは日常的に起きる)
#   - **外部参照ゼロ**: 混入すると Artifact の CSP に publish 後まで気付けない
#   - **入力の型検証**: 列数不一致・未知の section・キーの typo を publish 前に落とす。
#     かつ **stack trace ではなく `html-brief: ` 付きのメッセージで落ちる**こと
#     (agent が JSON のどこを直せばよいか特定できるようにするため)
#   - **出力先ガード**: このレンダラは settings.json の allow リストに載っていて
#     確認プロンプト無しで走る。argv 経由で任意のファイルを上書きできてはならない
#   - **バーの幅**: レンダラが最大値から算出する計算そのもの
#
# ロケール非依存にするため LC_ALL は C に固定する (repo の lint-locale-pin 準拠)。
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
RENDERER="${RENDERER:-$REPO_ROOT/claude/skills/html-brief/render.mjs}"

# 実行ケース数の独立した期待値。ケースを増減したらここも直す
# (pass 数ではなく実行数を数える — ケースが黙って消えたときに気付くため)。
EXPECTED_CASES=35

if [ ! -f "$RENDERER" ]; then
  echo "ERROR: renderer not found: $RENDERER" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: node not installed (Brewfile: brew \"node\")" >&2
  exit 1
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/html-brief.XXXXXX")"
OUTSIDE_TMP="$REPO_ROOT/.html-brief-outside-tmp.html"
cleanup() {
  [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"
  rm -f "$OUTSIDE_TMP"
}
trap cleanup EXIT

pass=0
fail=0
cases=0

ok() { cases=$((cases + 1)); pass=$((pass + 1)); }
ng() { cases=$((cases + 1)); echo "FAIL $1"; fail=$((fail + 1)); }

# render <json> [outpath] — stdout は OUT、stderr は ERR、終了コードは RC に入れる。
# stdout と stderr を混ぜない (混ぜると「HTML の形式」の検査に stderr が紛れ込む)。
RC=0
OUT=""
ERR=""
render() {
  printf '%s' "$1" > "$WORKDIR/in.json"
  set +e
  if [ "$#" -ge 2 ]; then
    OUT="$(node "$RENDERER" "$WORKDIR/in.json" "$2" 2>"$WORKDIR/err.txt")"
  else
    OUT="$(node "$RENDERER" "$WORKDIR/in.json" 2>"$WORKDIR/err.txt")"
  fi
  RC=$?
  set -e
  ERR="$(cat "$WORKDIR/err.txt")"
}

# stderr がクリーンか — 1 行目が `html-brief: ` で始まり、かつ **stack frame
# (`    at ...`) を含まない**こと。fail() は stderr に書いてから exit するので、
# 1 行目だけを見ると「メッセージを出してから throw した」ケースを見逃す
# (実際に fail() の process.exit を throw に置換した mutant が 1 行目検査を
# すり抜けた)。frame の有無で見る。
stderr_is_clean() { # <stderr ファイル>
  head -1 "$1" | grep -q '^html-brief: ' || return 1
  ! grep -qE '^[[:space:]]+at ' "$1"
}

# 検証エラーが「クリーンに」落ちたか
clean_error() {
  [ "$RC" -ne 0 ] && stderr_is_clean "$WORKDIR/err.txt"
}

# expect_reject <name> <json> — クリーンな検証エラーになることを assert する
expect_reject() {
  render "$2"
  if clean_error; then ok; else ng "$1 (rc=$RC, err=$(printf '%s' "$ERR" | head -1))"; fi
}

MINIMAL='{
  "title": "T",
  "verdict": "V",
  "sections": [{"type": "notes", "title": "S", "body": "B"}]
}'

# --- 1. 最小構成が描画できる ---
render "$MINIMAL"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '<title>T</title>' \
  && printf '%s' "$OUT" | grep -q '結論'; then ok; else ng "minimal renders (rc=$RC)"; fi

# charset を出す (file:// で開いたときに文字化けしないため)
if printf '%s' "$OUT" | grep -q '<meta charset="utf-8">'; then ok; else ng "charset present"; fi

# --- 2. 必須フィールドの欠落を落とす ---
expect_reject "missing title rejected" \
  '{"verdict": "V", "sections": [{"type": "notes", "body": "B"}]}'
expect_reject "missing verdict rejected" \
  '{"title": "T", "sections": [{"type": "notes", "body": "B"}]}'
expect_reject "empty sections rejected" \
  '{"title": "T", "verdict": "V", "sections": []}'
expect_reject "top level array rejected" '[]'

# --- 3. 未知の section type / 未知のキーを落とす ---
expect_reject "unknown section type rejected" \
  '{"title": "T", "verdict": "V", "sections": [{"type": "gallery"}]}'
expect_reject "unknown top-level key rejected" \
  '{"title": "T", "verdict": "V", "titel": "x", "sections": [{"type": "notes", "body": "B"}]}'
expect_reject "unknown section key rejected" \
  '{"title": "T", "verdict": "V", "sections": [{"type": "series", "points": [{"label": "a", "value": 1}], "takeaways": "typo"}]}'

# --- 4. 壊れた JSON を落とす ---
render '{"title": "T",'
if clean_error && printf '%s' "$ERR" | grep -q 'JSON'; then ok; else ng "broken JSON rejected (rc=$RC)"; fi

# --- 5. null 要素で stack trace にしない ---
expect_reject "null row rejected" \
  '{"title": "T", "verdict": "V", "sections": [{"type": "decision", "columns": ["a", "判定"], "rows": [null]}]}'
expect_reject "null step rejected" \
  '{"title": "T", "verdict": "V", "sections": [{"type": "walkthrough", "steps": [null]}]}'
expect_reject "null point rejected" \
  '{"title": "T", "verdict": "V", "sections": [{"type": "series", "points": [null]}]}'
expect_reject "null details rejected" \
  '{"title": "T", "verdict": "V", "sections": [{"type": "notes", "body": "B", "details": null}]}'
expect_reject "null section rejected" \
  '{"title": "T", "verdict": "V", "sections": [null]}'

# --- 6. decision: 列数と cells の不一致を落とす ---
expect_reject "decision cells/columns mismatch rejected" \
  '{"title": "T", "verdict": "V", "sections": [{"type": "decision",
    "columns": ["a", "判定", "c"],
    "rows": [{"label": "x", "badge": {"kind": "ok", "text": "採用"}, "cells": ["p", "q"]}]}]}'

# 列数が合っていれば通る
render '{"title": "T", "verdict": "V", "sections": [{"type": "decision",
  "columns": ["a", "判定", "c"],
  "rows": [{"label": "x", "badge": {"kind": "ok", "text": "採用"}, "cells": ["p"]}]}]}'
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'class="badge ok"'; then ok; else ng "decision renders (rc=$RC)"; fi

# --- 7. 不正な badge.kind を落とす ---
expect_reject "bad badge kind rejected" \
  '{"title": "T", "verdict": "V", "sections": [{"type": "decision",
    "columns": ["a", "判定"],
    "rows": [{"label": "x", "badge": {"kind": "danger", "text": "!"}, "cells": []}]}]}'

# --- 8. エスケープ: 入力の HTML がそのまま出力に出ない ---
render '{"title": "<script>alert(1)</script>", "verdict": "a & b \"c\" '"'"'d'"'"'",
  "sections": [{"type": "notes", "body": "<img src=x>"}]}'
if [ "$RC" -eq 0 ] \
  && ! printf '%s' "$OUT" | grep -q '<script>alert' \
  && ! printf '%s' "$OUT" | grep -q '<img src=x>' \
  && printf '%s' "$OUT" | grep -q '&lt;script&gt;' \
  && printf '%s' "$OUT" | grep -q '&amp;' \
  && printf '%s' "$OUT" | grep -q '&#39;'; then ok; else ng "escaping (rc=$RC)"; fi

# --- 9. 外部ホストへの参照がゼロ (CSP 準拠) ---
# 全 section 型を含む入力に対して検査する (型ごとに経路が違うため)
ALL_TYPES='{"title": "T", "verdict": "V", "sections": [
  {"type": "notes", "body": "B"},
  {"type": "decision", "columns": ["a", "判定"], "rows": [{"label": "x", "cells": []}]},
  {"type": "walkthrough", "steps": [{"title": "s", "code": "c"}]},
  {"type": "series", "points": [{"label": "p", "value": 1}]},
  {"type": "diagram", "mermaid": "graph TD;A-->B;"}
]}'
render "$ALL_TYPES"
if [ "$RC" -eq 0 ] && ! printf '%s' "$OUT" | grep -qE 'https?://|url\(|<script|src='; then
  ok; else ng "no external references (rc=$RC)"; fi

# --- 10. series: バーの幅を最大値から算出する ---
render '{"title": "T", "verdict": "V", "sections": [{"type": "series",
  "points": [{"label": "a", "value": 10}, {"label": "b", "value": 5}]}]}'
if [ "$RC" -eq 0 ] \
  && printf '%s' "$OUT" | grep -q 'width: 100%' \
  && printf '%s' "$OUT" | grep -q 'width: 50%'; then ok; else ng "series bar widths (rc=$RC)"; fi

# 全て 0 でもゼロ除算で壊れない
render '{"title": "T", "verdict": "V", "sections": [{"type": "series",
  "points": [{"label": "a", "value": 0}]}]}'
if [ "$RC" -eq 0 ]; then ok; else ng "series all-zero (rc=$RC)"; fi

expect_reject "negative series value rejected" \
  '{"title": "T", "verdict": "V", "sections": [{"type": "series",
    "points": [{"label": "a", "value": -1}]}]}'

# --- 11. インライン記法は `code` だけ ---
# backtick はシェルのコマンド置換と衝突するので printf で組み立てる (SC2016 回避)
BT='\140'
render "$(printf '{"title": "T", "verdict": "%bx%b と **y**", "sections": [{"type": "notes", "body": "B"}]}' "$BT" "$BT")"
if [ "$RC" -eq 0 ] \
  && printf '%s' "$OUT" | grep -q '<code>x</code>' \
  && printf '%s' "$OUT" | grep -q '\*\*y\*\*'; then ok; else ng "inline code only (rc=$RC)"; fi

# --- 12. diagram / walkthrough の描画 ---
render '{"title": "T", "verdict": "V", "sections": [{"type": "diagram", "mermaid": "graph TD;A-->B;"}]}'
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '<pre class="mermaid">'; then ok; else ng "diagram renders (rc=$RC)"; fi

render '{"title": "T", "verdict": "V", "sections": [{"type": "walkthrough",
  "steps": [{"title": "s1", "body": "b1", "code": "cmd"}]}]}'
if [ "$RC" -eq 0 ] \
  && printf '%s' "$OUT" | grep -q '<ol class="steps">' \
  && printf '%s' "$OUT" | grep -q '<pre><code>cmd</code></pre>'; then ok; else ng "walkthrough renders (rc=$RC)"; fi

# --- 13. 出力先ガード ---
# 確認プロンプト無しで走る前提なので、argv 経由で任意のファイルを壊せてはならない。
printf '%s' "$MINIMAL" > "$WORKDIR/guard.json"

guard_reject() { # <name> <outpath> <victim-path> <victim-content>
  set +e
  node "$RENDERER" "$WORKDIR/guard.json" "$2" >/dev/null 2>"$WORKDIR/err.txt"
  local rc=$?
  set -e
  local head_line
  head_line="$(head -1 "$WORKDIR/err.txt")"
  if [ "$rc" -ne 0 ] \
    && stderr_is_clean "$WORKDIR/err.txt" \
    && [ "$(cat "$3")" = "$4" ]; then
    ok
  else
    ng "$1 (rc=$rc, err=$head_line)"
  fi
}

# .html 以外への書き込みを拒否する
printf 'original' > "$WORKDIR/victim.txt"
guard_reject "non-html output path rejected" "$WORKDIR/victim.txt" "$WORKDIR/victim.txt" "original"

# symlink 越しの書き込みを拒否する (拡張子チェックの迂回経路)
printf 'secret' > "$WORKDIR/secret.txt"
ln -s "$WORKDIR/secret.txt" "$WORKDIR/evil-symlink.html"
guard_reject "symlink output path rejected" "$WORKDIR/evil-symlink.html" "$WORKDIR/secret.txt" "secret"

# hardlink 越しの書き込みを拒否する (symlink と同じ効果を別経路で得られる)
printf 'hardsecret' > "$WORKDIR/hardsecret.txt"
ln "$WORKDIR/hardsecret.txt" "$WORKDIR/evil-hardlink.html"
guard_reject "hardlink output path rejected" "$WORKDIR/evil-hardlink.html" "$WORKDIR/hardsecret.txt" "hardsecret"

# ディレクトリ symlink 越しの迂回を拒否する (親を realpath で解決する)
mkdir -p "$WORKDIR/realdir"
printf 'indir' > "$WORKDIR/realdir/target.html"
ln -s "$WORKDIR/realdir" "$WORKDIR/dirlink"
# realdir 自体は一時ディレクトリ配下なのでここは通る (= 通ることを確認する)
set +e
node "$RENDERER" "$WORKDIR/guard.json" "$WORKDIR/dirlink/target.html" >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ] && grep -q '<title>T</title>' "$WORKDIR/realdir/target.html"; then
  ok; else ng "dir symlink inside tmp accepted (rc=$rc)"; fi

# 一時ディレクトリの外 (作業中の repo) への書き込みを拒否する
set +e
node "$RENDERER" "$WORKDIR/guard.json" "$OUTSIDE_TMP" >/dev/null 2>"$WORKDIR/err.txt"
rc=$?
set -e
if [ "$rc" -ne 0 ] \
  && head -1 "$WORKDIR/err.txt" | grep -q '^html-brief: ' \
  && [ ! -e "$OUTSIDE_TMP" ]; then ok; else ng "outside-tmp output rejected (rc=$rc)"; fi

# 親ディレクトリが無いときも stack trace にしない
set +e
node "$RENDERER" "$WORKDIR/guard.json" "$WORKDIR/nodir/out.html" >/dev/null 2>"$WORKDIR/err.txt"
rc=$?
set -e
if [ "$rc" -ne 0 ] && head -1 "$WORKDIR/err.txt" | grep -q '^html-brief: '; then
  ok; else ng "missing parent dir rejected cleanly (rc=$rc)"; fi

# 正常な .html には書ける / 同じパスへの再書き込み (再 deploy) もできる
set +e
node "$RENDERER" "$WORKDIR/guard.json" "$WORKDIR/fine.html" >/dev/null 2>&1
rc=$?
node "$RENDERER" "$WORKDIR/guard.json" "$WORKDIR/fine.html" >/dev/null 2>&1
rc2=$?
set -e
if [ "$rc" -eq 0 ] && [ "$rc2" -eq 0 ] && grep -q '<title>T</title>' "$WORKDIR/fine.html"; then
  ok; else ng "html output path accepted and rewritable (rc=$rc/$rc2)"; fi

# --- 14. 入力が読めない / style.css が無い場合も stack trace にしない ---
set +e
node "$RENDERER" "$WORKDIR/does-not-exist.json" >/dev/null 2>"$WORKDIR/err.txt"
rc=$?
set -e
if [ "$rc" -ne 0 ] && head -1 "$WORKDIR/err.txt" | grep -q '^html-brief: '; then
  ok; else ng "missing input rejected cleanly (rc=$rc)"; fi

# style.css の隣に置いたコピーを、css 無しの状態で実行する
cp "$RENDERER" "$WORKDIR/lonely-render.mjs"
set +e
node "$WORKDIR/lonely-render.mjs" "$WORKDIR/guard.json" >/dev/null 2>"$WORKDIR/err.txt"
rc=$?
set -e
if [ "$rc" -ne 0 ] && head -1 "$WORKDIR/err.txt" | grep -q '^html-brief: '; then
  ok; else ng "missing style.css rejected cleanly (rc=$rc)"; fi

# --- ケース数の下限検査 ---
if [ "$cases" -ne "$EXPECTED_CASES" ]; then
  echo "FAIL case count: expected=$EXPECTED_CASES got=$cases (ケースを増減したら EXPECTED_CASES も直す)"
  fail=$((fail + 1))
fi

echo "html-brief renderer tests: $pass passed, $fail failed ($cases cases)"
[ "$fail" -eq 0 ]
