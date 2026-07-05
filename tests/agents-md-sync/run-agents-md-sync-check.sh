#!/usr/bin/env bash
set -euo pipefail

# agents/AGENTS.md と codex/AGENTS.md は、共通部分を手動コピーで同期する運用
# になっている (Codex CLI 向けにセキュリティ規約セクションを追加した派生
# ファイルが codex/AGENTS.md)。手動コピーは drift (ズレ) が機械的に検出され
# ないと気づかれずに放置されるため、PR #69 の /simplify altitude 指摘を受けて
# このチェックを追加した。
#
# 検証する不変条件:
#   1. タイトル (1 行目) は意図的に異なる:
#      agents 側 "# AI Agent Guidelines" / codex 側は "(Codex CLI)" 付き。
#      taitle drift・suffix 消失の regression を防ぐため exact match で assert する。
#   2. 共通部分の同一性: agents 側の 2 行目〜末尾と、codex 側の 2 行目〜
#      「## セキュリティ規約」直前が同一であること。
#   3. codex 側に「## セキュリティ規約」の見出しが存在すること
#      (前提となる構造がなければ抽出ロジックが無意味になるため exit 1)
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

# --- 2. codex 側に構造前提のマーカー行が存在するか ---
if ! grep -qF "$SECURITY_MARKER" "$CODEX_MD"; then
  echo "ERROR: codex AGENTS.md に '$SECURITY_MARKER' 行が見つかりません (構造前提エラー)" >&2
  exit 1
fi

# --- 3. 共通部分の抽出 ---
# agents 側: 2 行目〜ファイル末尾
tail -n +2 "$AGENTS_MD" > "$WORKDIR/agents_common.txt"

# codex 側: 2 行目〜「## セキュリティ規約」行の直前まで
awk -v marker="$SECURITY_MARKER" '
  $0 == marker { exit }
  NR >= 2 { print }
' "$CODEX_MD" > "$WORKDIR/codex_common.txt"

# 両抽出とも、末尾の空行 (連続する空行含む) を正規化してから比較する。
# codex 側はセクション区切りの空行がマーカー直前に入るため、正規化しないと
# 内容が同一でも drift 扱いになってしまう。
# ($(...) コマンド置換は末尾の改行をすべて取り除く性質を利用して正規化する)
agents_common="$(cat "$WORKDIR/agents_common.txt")"
codex_common="$(cat "$WORKDIR/codex_common.txt")"
printf '%s\n' "$agents_common" > "$WORKDIR/agents_common.normalized.txt"
printf '%s\n' "$codex_common" > "$WORKDIR/codex_common.normalized.txt"

if ! diff -u "$WORKDIR/agents_common.normalized.txt" "$WORKDIR/codex_common.normalized.txt"; then
  echo "" >&2
  echo "FAIL: agents/AGENTS.md と codex/AGENTS.md の共通部分に drift があります" >&2
  echo "  手動コピー同期の対象なので、両方が一致するよう手で修正してください" >&2
  exit 1
fi

common_lines="$(wc -l < "$WORKDIR/agents_common.normalized.txt" | tr -d ' ')"
echo "agents-md sync: OK (common part $common_lines lines identical)"
exit 0
