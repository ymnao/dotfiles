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
#   - **出力先ガード**: argv 経由で作業中 repo のファイルや任意の inode を
#     誤って上書きできてはならない (誤爆防止。セキュリティ境界ではない)
#   - **バーの幅**: レンダラが最大値から算出する計算そのもの
#
# ロケール非依存にするため LC_ALL は C に固定する (repo の lint-locale-pin 準拠)。
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
RENDERER="${RENDERER:-$REPO_ROOT/claude/skills/html-brief/render.mjs}"

# 実行ケース数の独立した期待値。ケースを増減したらここも直す
# (pass 数ではなく実行数を数える — ケースが黙って消えたときに気付くため)。
EXPECTED_CASES=56

if [ ! -f "$RENDERER" ]; then
  echo "ERROR: renderer not found: $RENDERER" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: node not installed (Brewfile: brew \"node\")" >&2
  exit 1
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/html-brief.XXXXXX")"

# 「一時ディレクトリ外」のケース用の作業場所。**固定名を使わない** — repo 直下に
# 固定名のファイルを作ると、同名の既存ファイルを上書きして壊しうる。
# /var/tmp が使えればそちらが素直だが、agent の sandbox では書けないため repo 直下に
# 一意なディレクトリを掘る (中身ごと cleanup で消す)。
OUTSIDE_ROOT="$(mktemp -d "$REPO_ROOT/.html-brief-outside.XXXXXX")"
OUTSIDE_TMP="$OUTSIDE_ROOT/outside.html"

# trap は作業ディレクトリを作った直後に張る。この後の前提検証が exit しうるので、
# 後ろに置くと作業ディレクトリが残る。
cleanup() {
  [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"
  [ -n "${OUTSIDE_ROOT:-}" ] && rm -rf "$OUTSIDE_ROOT"
}
trap cleanup EXIT

# OUTSIDE_ROOT が本当に一時ディレクトリの外にあることを確かめる。ここが崩れると
# レンダラが正しく受理してしまい、outside-tmp ケースが誤 FAIL する。
# skip ではなく明示的に落とす (skip はケース数の下限検査を素通しにするため)。
real_outside="$(cd "$OUTSIDE_ROOT" && pwd -P)"
for tmp_root in "${TMPDIR:-/tmp}" /tmp; do
  real_root="$(cd "$tmp_root" 2>/dev/null && pwd -P || true)"
  [ -n "$real_root" ] || continue
  case "$real_outside/" in
    "$real_root"/*)
      echo "ERROR: fixture ($real_outside) が一時ディレクトリ配下 ($real_root) にあるため outside-tmp ケースを実行できません" >&2
      exit 1
      ;;
  esac
done

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
# cells が配列でないとき、空配列に落とさず落とす
# (落とすと「書いた内容が rc=0 のまま消える」経路になる)
expect_reject "non-array cells rejected" \
  '{"title": "T", "verdict": "V", "sections": [{"type": "decision",
    "columns": ["a", "判定"],
    "rows": [{"label": "x", "cells": "書いたつもりの根拠"}]}]}'

# 任意フィールドの型も見る ([object Object] がページに出るのを防ぐ)
expect_reject "non-string optional field rejected" \
  '{"title": "T", "verdict": "V", "sections": [{"type": "series",
    "unit": {"a": 1}, "points": [{"label": "p", "value": 1}]}]}'
expect_reject "non-string top-level optional rejected" \
  '{"title": "T", "verdict": "V", "date": ["2026-08-06"],
    "sections": [{"type": "notes", "body": "B"}]}'

expect_reject "non-string column rejected" \
  '{"title": "T", "verdict": "V", "sections": [{"type": "decision",
    "columns": ["a", {"b": 1}],
    "rows": [{"label": "x", "cells": []}]}]}'
expect_reject "non-string cell rejected" \
  '{"title": "T", "verdict": "V", "sections": [{"type": "decision",
    "columns": ["a", "判定", "c"],
    "rows": [{"label": "x", "cells": [{"b": 1}]}]}]}'

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
# 検査は scheme に依存しない形にする (相対パスの @import / href / srcset も拒否)
EXTERNAL_REF_RE='https?://|url\(|@import|<script|src=|srcset=|href='
render "$ALL_TYPES"
if [ "$RC" -eq 0 ] && ! printf '%s' "$OUT" | grep -qE "$EXTERNAL_REF_RE"; then
  ok; else ng "no external references (rc=$RC)"; fi

# 検査自体が効いていることを、既知の陽性で確かめる (パターンの空振り防止)
if printf '<link href="x.css">' | grep -qE "$EXTERNAL_REF_RE" \
  && printf '@import "x.css";' | grep -qE "$EXTERNAL_REF_RE" \
  && printf '<img srcset="x.png">' | grep -qE "$EXTERNAL_REF_RE"; then
  ok; else ng "external-ref pattern detects known positives"; fi

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

# --- 11. インライン記法は `code` と **bold** の 2 つだけ ---
# backtick はシェルのコマンド置換と衝突するので printf で組み立てる (SC2016 回避)
BT='\140'
render "$(printf '{"title": "T", "verdict": "%bx%b と **y** と _z_", "sections": [{"type": "notes", "body": "B"}]}' "$BT" "$BT")"
if [ "$RC" -eq 0 ] \
  && printf '%s' "$OUT" | grep -q '<code>x</code>' \
  && printf '%s' "$OUT" | grep -q '<strong>y</strong>' \
  && ! printf '%s' "$OUT" | grep -q '\*\*y\*\*' \
  && printf '%s' "$OUT" | grep -q '_z_'; then ok; else ng "inline code and bold only (rc=$RC)"; fi

# --- 12. diagram / walkthrough の描画 ---
render '{"title": "T", "verdict": "V", "sections": [{"type": "diagram", "mermaid": "graph TD;A-->B;"}]}'
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '<pre class="mermaid">'; then ok; else ng "diagram renders (rc=$RC)"; fi

render '{"title": "T", "verdict": "V", "sections": [{"type": "walkthrough",
  "steps": [{"title": "s1", "body": "b1", "code": "cmd"}]}]}'
if [ "$RC" -eq 0 ] \
  && printf '%s' "$OUT" | grep -q '<ol class="steps">' \
  && printf '%s' "$OUT" | grep -q '<pre><code>cmd</code></pre>'; then ok; else ng "walkthrough renders (rc=$RC)"; fi

# --- 12b. まだ測っていなかった分岐 ---
# details の正常描画と、summary / body 欠落の拒否
render '{"title": "T", "verdict": "V", "sections": [{"type": "notes", "body": "B",
  "details": {"summary": "S", "body": "D"}}]}'
if [ "$RC" -eq 0 ] \
  && printf '%s' "$OUT" | grep -q '<details><summary>S</summary>' \
  && printf '%s' "$OUT" | grep -q '<p>D</p>'; then ok; else ng "details renders (rc=$RC)"; fi

expect_reject "details missing summary rejected" \
  '{"title": "T", "verdict": "V", "sections": [{"type": "notes", "body": "B",
    "details": {"body": "D"}}]}'
expect_reject "details unknown key rejected" \
  '{"title": "T", "verdict": "V", "sections": [{"type": "notes", "body": "B",
    "details": {"summary": "S", "body": "D", "extra": "x"}}]}'

# columns が 1 列だけなら落とす (1 列目=対象 / 2 列目=判定 が前提)
expect_reject "single column rejected" \
  '{"title": "T", "verdict": "V", "sections": [{"type": "decision",
    "columns": ["a"], "rows": [{"label": "x"}]}]}'

# badge.kind 省略時は info に既定化する
render '{"title": "T", "verdict": "V", "sections": [{"type": "decision",
  "columns": ["a", "判定"], "rows": [{"label": "x", "badge": {"text": "情報"}}]}]}'
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'class="badge info"'; then
  ok; else ng "badge kind defaults to info (rc=$RC)"; fi

# 引数なしで起動したら usage を出してクリーンに落ちる
set +e
node "$RENDERER" >/dev/null 2>"$WORKDIR/err.txt"
rc=$?
set -e
if [ "$rc" -ne 0 ] && stderr_is_clean "$WORKDIR/err.txt" \
  && grep -q '使い方' "$WORKDIR/err.txt"; then ok; else ng "no-args usage (rc=$rc)"; fi

# 日本語・絵文字・結合文字が壊れずに残り、同じ入力の HTML 特殊文字はエスケープされる
render '{"title": "T", "verdict": "日本語 🎨 か゚ <b>", "sections": [{"type": "notes", "body": "B"}]}'
if [ "$RC" -eq 0 ] \
  && printf '%s' "$OUT" | grep -q '日本語 🎨 か゚' \
  && printf '%s' "$OUT" | grep -q '&lt;b&gt;'; then ok; else ng "unicode preserved (rc=$RC)"; fi

# --- 13. 出力先ガード ---
# argv の指すファイルを誤って壊さないことを測る。
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
if [ "$rc" -ne 0 ] && stderr_is_clean "$WORKDIR/err.txt" && [ ! -e "$OUTSIDE_TMP" ]; then
  ok; else ng "outside-tmp output rejected (rc=$rc)"; fi

# `..` で一時ディレクトリ制限を迂回できない。
# resolve() は `..` を字句的に畳むが、カーネルは symlink を辿ってから `..` を
# 解決するので、`<tmp>/dirlink/../x.html` はガードから見える場所とは別の場所に
# 書かれる。dirlink の実体を repo 内に置いて、実際に書かれないことを確かめる。
# `..` が symlink 自身を打ち消す形にするのが要点。lexical には
# `$WORKDIR/<victim>` (= 一時ディレクトリ配下、ガードは通す) に見えるが、
# カーネルは repo-link を辿ってから `..` を解決するので repo 直下に書かれる。
mkdir -p "$OUTSIDE_ROOT/sub"
ln -s "$OUTSIDE_ROOT/sub" "$WORKDIR/outside-link"
ESCAPE_VICTIM="$OUTSIDE_ROOT/escape-victim.html"
printf 'ORIGINAL' > "$ESCAPE_VICTIM"
set +e
node "$RENDERER" "$WORKDIR/guard.json" \
  "$WORKDIR/outside-link/../escape-victim.html" \
  >/dev/null 2>"$WORKDIR/err.txt"
rc=$?
set -e
if [ "$rc" -ne 0 ] && stderr_is_clean "$WORKDIR/err.txt" \
  && [ "$(cat "$ESCAPE_VICTIM")" = "ORIGINAL" ]; then
  ok; else ng "dotdot escape rejected (rc=$rc)"; fi

# 親ディレクトリが無いときも stack trace にしない
set +e
node "$RENDERER" "$WORKDIR/guard.json" "$WORKDIR/nodir/out.html" >/dev/null 2>"$WORKDIR/err.txt"
rc=$?
set -e
if [ "$rc" -ne 0 ] && stderr_is_clean "$WORKDIR/err.txt"; then
  ok; else ng "missing parent dir rejected cleanly (rc=$rc)"; fi

# 一時ディレクトリの候補は TMPDIR と /tmp の 2 つ。**両方**が受理側に効いている
# ことを測る (片方に戻す変更が全 pass で通らないように)。動機は「harness が渡す
# scratchpad と対話 shell の TMPDIR が別物の環境で、正常な出力先が拒否される」退行。

# (a) TMPDIR が /tmp の外を指していても、/tmp 配下への出力は受理される
set +e
TMPDIR="$OUTSIDE_ROOT" node "$RENDERER" "$WORKDIR/guard.json" "$WORKDIR/root-tmp.html" \
  >/dev/null 2>"$WORKDIR/err.txt"
rc=$?
set -e
if [ "$rc" -eq 0 ] && grep -q '<title>T</title>' "$WORKDIR/root-tmp.html"; then
  ok; else ng "/tmp accepted as root when TMPDIR points elsewhere (rc=$rc)"; fi

# (b) TMPDIR 側も受理側に効く (TMPDIR 配下なら /tmp の外でも書ける)
TMPDIR_PROBE="$OUTSIDE_ROOT/tmpdir-probe.html"
set +e
TMPDIR="$OUTSIDE_ROOT" node "$RENDERER" "$WORKDIR/guard.json" "$TMPDIR_PROBE" \
  >/dev/null 2>"$WORKDIR/err.txt"
rc=$?
set -e
if [ "$rc" -eq 0 ] && grep -q '<title>T</title>' "$TMPDIR_PROBE"; then
  ok; else ng "TMPDIR accepted as root (rc=$rc)"; fi

# TMPDIR が解決できない場所を指していても stack trace にしない
set +e
TMPDIR="$WORKDIR/does-not-exist" node "$RENDERER" "$WORKDIR/guard.json" "$WORKDIR/tmpdir-probe.html" \
  >/dev/null 2>"$WORKDIR/err.txt"
rc=$?
set -e
# /tmp が候補に残るので成功しうる。落ちる場合でも stack trace であってはならない
if [ "$rc" -eq 0 ] || stderr_is_clean "$WORKDIR/err.txt"; then
  ok; else ng "broken TMPDIR handled cleanly (rc=$rc)"; fi

# 正常な .html には書ける / 同じパスへの再書き込み (再 deploy) もできる
set +e
node "$RENDERER" "$WORKDIR/guard.json" "$WORKDIR/fine.html" >/dev/null 2>&1
rc=$?
node "$RENDERER" "$WORKDIR/guard.json" "$WORKDIR/fine.html" >/dev/null 2>&1
rc2=$?
set -e
if [ "$rc" -eq 0 ] && [ "$rc2" -eq 0 ] && grep -q '<title>T</title>' "$WORKDIR/fine.html"; then
  ok; else ng "html output path accepted and rewritable (rc=$rc/$rc2)"; fi

# world-writable な親ディレクトリ (/tmp 直下は 1777) への出力を拒否する。
# 共有一時領域は検証と open の間に親 symlink を差し替えられるため受けない。
set +e
node "$RENDERER" "$WORKDIR/guard.json" "/tmp/html-brief-world-writable-probe.html" \
  >/dev/null 2>"$WORKDIR/err.txt"
rc=$?
set -e
if [ "$rc" -ne 0 ] && stderr_is_clean "$WORKDIR/err.txt" \
  && [ ! -e "/tmp/html-brief-world-writable-probe.html" ]; then
  ok; else ng "world-writable parent rejected (rc=$rc)"; fi

# 生成物は 0600 で作る (調査内容を含みうるので他ユーザーに読ませない)。
# BSD / GNU 両対応のため stat ではなく find -perm で判定する。
if [ -n "$(find "$WORKDIR" -maxdepth 1 -name fine.html -perm 600)" ]; then
  ok; else ng "output mode is 0600"; fi

# 入力は通常ファイルに限る (/dev/zero を渡しても返ってこなくならない)
set +e
node "$RENDERER" /dev/zero >/dev/null 2>"$WORKDIR/err.txt"
rc=$?
set -e
if [ "$rc" -ne 0 ] && stderr_is_clean "$WORKDIR/err.txt"; then
  ok; else ng "non-regular input rejected (rc=$rc)"; fi

# --- 14. 入力が読めない / style.css が無い場合も stack trace にしない ---
set +e
node "$RENDERER" "$WORKDIR/does-not-exist.json" >/dev/null 2>"$WORKDIR/err.txt"
rc=$?
set -e
if [ "$rc" -ne 0 ] && stderr_is_clean "$WORKDIR/err.txt"; then
  ok; else ng "missing input rejected cleanly (rc=$rc)"; fi

# JSON でないファイルを渡しても、その中身を stderr に出さない
printf 'AWS_SECRET_ACCESS_KEY=leak-me\n' > "$WORKDIR/not-json.env"
set +e
node "$RENDERER" "$WORKDIR/not-json.env" >/dev/null 2>"$WORKDIR/err.txt"
rc=$?
set -e
if [ "$rc" -ne 0 ] && stderr_is_clean "$WORKDIR/err.txt" \
  && ! grep -q 'AWS_SECRET' "$WORKDIR/err.txt"; then
  ok; else ng "input content not echoed on parse error (rc=$rc)"; fi

# style.css の隣に置いたコピーを、css 無しの状態で実行する
cp "$RENDERER" "$WORKDIR/lonely-render.mjs"
set +e
node "$WORKDIR/lonely-render.mjs" "$WORKDIR/guard.json" >/dev/null 2>"$WORKDIR/err.txt"
rc=$?
set -e
if [ "$rc" -ne 0 ] && stderr_is_clean "$WORKDIR/err.txt"; then
  ok; else ng "missing style.css rejected cleanly (rc=$rc)"; fi

# --- ケース数の下限検査 ---
if [ "$cases" -ne "$EXPECTED_CASES" ]; then
  echo "FAIL case count: expected=$EXPECTED_CASES got=$cases (ケースを増減したら EXPECTED_CASES も直す)"
  fail=$((fail + 1))
fi

echo "html-brief renderer tests: $pass passed, $fail failed ($cases cases)"
[ "$fail" -eq 0 ]
