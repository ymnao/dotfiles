#!/usr/bin/env bash
set -euo pipefail

# agents/AGENTS.md と codex/AGENTS.md は、共通部分を手動コピーで同期する運用
# になっている (codex/AGENTS.md 側は共通部分にセキュリティ規約セクションを
# 追加している)。手動コピーは drift (ズレ) が機械的に検出されないと気づかれず
# に放置されるため、このチェックを追加した。両ファイルは同時編集する。
#
# 検証する不変条件:
#   1. タイトル (1 行目) は意図的に異なる:
#      agents 側 "# AI Agent Guidelines" / codex 側は "(Codex CLI)" 付き。
#      title drift・suffix 消失の regression を防ぐため exact match で assert する。
#   2. codex 側に「## セキュリティ規約」の見出しが存在すること
#      (前提となる構造がなければ抽出ロジックが無意味になるため exit 1)
#   3. 共通部分の同一性: agents 側の 2 行目〜末尾と、codex 側の 2 行目〜
#      「## セキュリティ規約」直前が同一であること。
#
# 行番号のハードコードはしない (行数が変わっても機能するよう、見出し行を
# マーカーにした awk 抽出で共通部分を切り出す)。
#
# ファイルパスは環境変数 AGENTS_MD / CODEX_MD で上書き可能
# (classify-risk テストの CLASSIFIER 同様、負テストを repo の実ファイルを
# 書き換えずに実施するため)。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
AGENTS_MD="${AGENTS_MD:-$REPO_ROOT/agents/AGENTS.md}"
CODEX_MD="${CODEX_MD:-$REPO_ROOT/codex/AGENTS.md}"

if [ ! -f "$AGENTS_MD" ]; then
  echo "ERROR: agents AGENTS.md not found: $AGENTS_MD" >&2
  exit 1
fi
if [ ! -f "$CODEX_MD" ]; then
  echo "ERROR: codex AGENTS.md not found: $CODEX_MD" >&2
  exit 1
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/agents-md-sync.XXXXXX")"
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT

SECURITY_MARKER="## セキュリティ規約"

# --- 1. タイトル行の exact match assert ---
agents_title="$(head -n 1 "$AGENTS_MD")"
codex_title="$(head -n 1 "$CODEX_MD")"

if [ "$agents_title" != "# AI Agent Guidelines" ]; then
  echo "FAIL: agents AGENTS.md のタイトルが想定と異なります" >&2
  echo "  expected: # AI Agent Guidelines" >&2
  echo "  actual:   $agents_title" >&2
  exit 1
fi
if [ "$codex_title" != "# AI Agent Guidelines (Codex CLI)" ]; then
  echo "FAIL: codex AGENTS.md のタイトルが想定と異なります" >&2
  echo "  expected: # AI Agent Guidelines (Codex CLI)" >&2
  echo "  actual:   $codex_title" >&2
  exit 1
fi

# .editorconfig で md ファイルの trailing whitespace 除去を無効化しているため、
# マーカー行の比較は行末空白を無視する形で行う (無視しないと trailing space が
# 混入した瞬間に「マーカー不在」の誤誘導的エラーになる)。この方針は step 2 の
# 存在確認と step 3 の awk 抽出の両方で揃える。

# --- 2. codex 側に構造前提のマーカー行が存在するか ---
if ! grep -qE "^${SECURITY_MARKER}[[:space:]]*$" "$CODEX_MD"; then
  echo "ERROR: codex AGENTS.md に '$SECURITY_MARKER' 行が見つかりません (構造前提エラー)" >&2
  exit 1
fi

# --- 3. 共通部分の抽出 ---
# 末尾の空行 (連続する空行含む) の扱いを両側で揃えないと、内容が同一でも
# drift 扱いになる (codex 側はセクション区切りの空行がマーカー直前に入るため)。
# ↓ $(...) コマンド置換が末尾の改行をすべて除去し、その後の printf が改行を
# 1 個だけ付け直すことで、両抽出とも「末尾改行 1 個」に正規化される。

# agents 側: 2 行目〜ファイル末尾
agents_common="$(tail -n +2 "$AGENTS_MD")"

# codex 側: 2 行目〜「## セキュリティ規約」行の直前まで
# ($0 から行末空白を除いた形と marker を比較。step 2 と同じ寛容さで揃える)
codex_common="$(awk -v marker="$SECURITY_MARKER" '
  { line = $0; sub(/[ \t]+$/, "", line) }
  # 空文字連結で string context を強制 (strnum 誤判定で数値見え文字列
  # 同士が 0 == 0 にマッチする awk 実装への portability 防御)
  line "" == marker "" { exit }
  NR >= 2 { print }
' "$CODEX_MD")"

printf '%s\n' "$agents_common" > "$WORKDIR/agents_common.txt"
printf '%s\n' "$codex_common" > "$WORKDIR/codex_common.txt"

if ! diff -u "$WORKDIR/agents_common.txt" "$WORKDIR/codex_common.txt"; then
  echo "" >&2
  echo "FAIL: agents/AGENTS.md と codex/AGENTS.md の共通部分に drift があります" >&2
  echo "  両ファイルを同時に編集する運用です。共通部分が一致するよう手で修正してください" >&2
  exit 1
fi

common_lines="$(wc -l < "$WORKDIR/agents_common.txt" | tr -d ' ')"
echo "agents-md sync: OK (common part $common_lines lines identical)"
exit 0
