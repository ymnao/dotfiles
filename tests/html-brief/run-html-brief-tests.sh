#!/usr/bin/env bash
set -euo pipefail

# html-brief の renderer (claude/skills/html-brief/render.mjs) の回帰テスト。
#
# 何を守るためのテストか (予防的な網羅ではなく、実際に壊れる経路):
#   - **エスケープ**: 入力の意味データがそのまま HTML に流れると、生成物が壊れる
#     (agent が書く文字列に <, &, " が混ざるのは日常的に起きる)
#   - **外部参照ゼロ**: 混入すると Artifact の CSP に publish 後まで気付けない
#   - **入力の型検証**: 列数不一致・未知の section・不正な badge を publish 前に落とす
#   - **バーの幅**: レンダラが最大値から算出する計算そのもの
#
# ロケール非依存にするため LC_ALL は C に固定する (repo の lint-locale-pin 準拠)。
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
RENDERER="${RENDERER:-$REPO_ROOT/claude/skills/html-brief/render.mjs}"

if [ ! -f "$RENDERER" ]; then
  echo "ERROR: renderer not found: $RENDERER" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: node not installed (Brewfile: brew \"node\")" >&2
  exit 1
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/html-brief.XXXXXX")"
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT

pass=0
fail=0

ok() { pass=$((pass + 1)); }
ng() { echo "FAIL $1"; fail=$((fail + 1)); }

# render <json> — 標準出力に HTML、rc を RC に入れる
RC=0
OUT=""
render() {
  printf '%s' "$1" > "$WORKDIR/in.json"
  set +e
  OUT="$(node "$RENDERER" "$WORKDIR/in.json" 2>&1)"
  RC=$?
  set -e
}

# 妥当な最小入力を組み立てる (各ケースはこれを壊して使う)
MINIMAL='{
  "title": "T",
  "verdict": "V",
  "sections": [{"type": "notes", "title": "S", "body": "B"}]
}'

# --- 1. 最小構成が描画できる ---
render "$MINIMAL"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '<title>T</title>' \
  && printf '%s' "$OUT" | grep -q '結論'; then ok; else ng "minimal renders (rc=$RC)"; fi

# --- 2. 必須フィールドの欠落を落とす ---
render '{"verdict": "V", "sections": [{"type": "notes", "body": "B"}]}'
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'title'; then ok; else ng "missing title rejected (rc=$RC)"; fi

render '{"title": "T", "sections": [{"type": "notes", "body": "B"}]}'
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'verdict'; then ok; else ng "missing verdict rejected (rc=$RC)"; fi

render '{"title": "T", "verdict": "V", "sections": []}'
if [ "$RC" -ne 0 ]; then ok; else ng "empty sections rejected (rc=$RC)"; fi

# --- 3. 未知の section type を落とす ---
render '{"title": "T", "verdict": "V", "sections": [{"type": "gallery"}]}'
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'gallery'; then ok; else ng "unknown section type rejected (rc=$RC)"; fi

# --- 4. 壊れた JSON を落とす ---
render '{"title": "T",'
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'JSON'; then ok; else ng "broken JSON rejected (rc=$RC)"; fi

# --- 5. decision: 列数と cells の不一致を落とす ---
render '{"title": "T", "verdict": "V", "sections": [{"type": "decision",
  "columns": ["a", "判定", "c"],
  "rows": [{"label": "x", "badge": {"kind": "ok", "text": "採用"}, "cells": ["p", "q"]}]}]}'
if [ "$RC" -ne 0 ]; then ok; else ng "decision cells/columns mismatch rejected (rc=$RC)"; fi

# 列数が合っていれば通る
render '{"title": "T", "verdict": "V", "sections": [{"type": "decision",
  "columns": ["a", "判定", "c"],
  "rows": [{"label": "x", "badge": {"kind": "ok", "text": "採用"}, "cells": ["p"]}]}]}'
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'class="badge ok"'; then ok; else ng "decision renders (rc=$RC)"; fi

# --- 6. 不正な badge.kind を落とす ---
render '{"title": "T", "verdict": "V", "sections": [{"type": "decision",
  "columns": ["a", "判定"],
  "rows": [{"label": "x", "badge": {"kind": "danger", "text": "!"}, "cells": []}]}]}'
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'danger'; then ok; else ng "bad badge kind rejected (rc=$RC)"; fi

# --- 7. エスケープ: 入力の HTML がそのまま出力に出ない ---
render '{"title": "<script>alert(1)</script>", "verdict": "a & b \"c\"",
  "sections": [{"type": "notes", "body": "<img src=x>"}]}'
if [ "$RC" -eq 0 ] \
  && ! printf '%s' "$OUT" | grep -q '<script>alert' \
  && ! printf '%s' "$OUT" | grep -q '<img src=x>' \
  && printf '%s' "$OUT" | grep -q '&lt;script&gt;' \
  && printf '%s' "$OUT" | grep -q '&amp;'; then ok; else ng "escaping (rc=$RC)"; fi

# --- 8. 外部ホストへの参照がゼロ (CSP 準拠) ---
render "$MINIMAL"
if [ "$RC" -eq 0 ] && ! printf '%s' "$OUT" | grep -qE 'https?://|url\(|<script|src='; then
  ok; else ng "no external references"; fi

# --- 9. series: バーの幅を最大値から算出する ---
render '{"title": "T", "verdict": "V", "sections": [{"type": "series",
  "points": [{"label": "a", "value": 10}, {"label": "b", "value": 5}]}]}'
if [ "$RC" -eq 0 ] \
  && printf '%s' "$OUT" | grep -q 'width: 100%' \
  && printf '%s' "$OUT" | grep -q 'width: 50%'; then ok; else ng "series bar widths (rc=$RC)"; fi

# 全て 0 でもゼロ除算で壊れない
render '{"title": "T", "verdict": "V", "sections": [{"type": "series",
  "points": [{"label": "a", "value": 0}]}]}'
if [ "$RC" -eq 0 ]; then ok; else ng "series all-zero (rc=$RC)"; fi

# 負値は落とす
render '{"title": "T", "verdict": "V", "sections": [{"type": "series",
  "points": [{"label": "a", "value": -1}]}]}'
if [ "$RC" -ne 0 ]; then ok; else ng "negative series value rejected (rc=$RC)"; fi

# --- 10. インライン記法は `code` だけ ---
# backtick はシェルのコマンド置換と衝突するので printf で組み立てる (SC2016 回避)
BT='\140'
render "$(printf '{"title": "T", "verdict": "%bx%b と **y**", "sections": [{"type": "notes", "body": "B"}]}' "$BT" "$BT")"
if [ "$RC" -eq 0 ] \
  && printf '%s' "$OUT" | grep -q '<code>x</code>' \
  && printf '%s' "$OUT" | grep -q '\*\*y\*\*'; then ok; else ng "inline code only (rc=$RC)"; fi

# --- 11. diagram は mermaid ブロックとして出す (画像を外部から読まない) ---
render '{"title": "T", "verdict": "V", "sections": [{"type": "diagram", "mermaid": "graph TD;A-->B;"}]}'
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '<pre class="mermaid">'; then ok; else ng "diagram renders (rc=$RC)"; fi

# --- 12. walkthrough が番号付きステップになる ---
render '{"title": "T", "verdict": "V", "sections": [{"type": "walkthrough",
  "steps": [{"title": "s1", "body": "b1", "code": "cmd"}]}]}'
if [ "$RC" -eq 0 ] \
  && printf '%s' "$OUT" | grep -q '<ol class="steps">' \
  && printf '%s' "$OUT" | grep -q '<pre><code>cmd</code></pre>'; then ok; else ng "walkthrough renders (rc=$RC)"; fi

echo "html-brief renderer tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
