#!/usr/bin/env bash
set -euo pipefail

# claude/skills/new-project/check-ready.sh の回帰テスト (issue #440)。
#
# 検証観点:
#   1. 3 項目が揃えば exit 0、出力は OK 行 3 本だけ
#   2. 各項目が 1 つ欠けると exit 1 で、欠けた項目だけが NG 行になる
#   3. workflow は .yaml でも、*.yml という名前のディレクトリでは数えない
#   4. .gitignore の行は完全一致 (コメントアウト・前方一致は NG)
#   5. 対象ディレクトリが無ければ exit 2
#   6. GitHub CLI を一度も呼ばない (失敗して呼び出しを記録する stub を PATH の先頭に置く)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
TARGET="$REPO_ROOT/claude/skills/new-project/check-ready.sh"

if [ ! -f "$TARGET" ]; then
  echo "ERROR: target not found: $TARGET" >&2
  exit 1
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/new-project-tests.XXXXXX")"
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT

STUB_BIN="$WORKDIR/bin"
GH_LOG="$WORKDIR/gh-called"
mkdir -p "$STUB_BIN"
printf '#!/bin/sh\necho "$*" >> "%s"\nexit 1\n' "$GH_LOG" > "$STUB_BIN/gh"
chmod +x "$STUB_BIN/gh"

pass=0
fail=0

# 3 項目が揃った repo を作る。
make_ready() {
  local d="$1"
  mkdir -p "$d/.github/workflows"
  printf '# x\n' > "$d/CLAUDE.md"
  printf 'name: ci\n' > "$d/.github/workflows/ci.yml"
  printf 'node_modules/\n\n# Claude Code\n.claude/settings.local.json\n' > "$d/.gitignore"
}

# $1: ケース名、$2: 対象 dir、$3: 期待 exit code、$4: 期待する stdout 全文
run_case() {
  local name="$1" dir="$2" want_rc="$3" want_out="$4"
  local out rc=0
  out="$(PATH="$STUB_BIN:$PATH" bash "$TARGET" "$dir" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq "$want_rc" ] && [ "$out" = "$want_out" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL $name: rc want=$want_rc got=$rc"
    echo "  want: $want_out"
    echo "  got:  $out"
  fi
}

OK_CLAUDE='OK  CLAUDE.md'
OK_WF='OK  .github/workflows/ の workflow'
OK_GI='OK  .gitignore の .claude/settings.local.json'
NG_CLAUDE='NG  CLAUDE.md — claude-init.sh でテンプレートをコピーする'
NG_WF='NG  .github/workflows/ の workflow — lint / test を実行する ci.yml を置く'
NG_GI='NG  .gitignore の .claude/settings.local.json — claude-init.sh が追記する行が無い'
nl='
'

d="$WORKDIR/ready"; make_ready "$d"
run_case "all ready" "$d" 0 "${OK_CLAUDE}${nl}${OK_WF}${nl}${OK_GI}"

d="$WORKDIR/no-claude"; make_ready "$d"; rm "$d/CLAUDE.md"
run_case "CLAUDE.md missing" "$d" 1 "${NG_CLAUDE}${nl}${OK_WF}${nl}${OK_GI}"

d="$WORKDIR/no-workflow"; make_ready "$d"; rm "$d/.github/workflows/ci.yml"
run_case "workflow missing" "$d" 1 "${OK_CLAUDE}${nl}${NG_WF}${nl}${OK_GI}"

d="$WORKDIR/yaml"; make_ready "$d"; mv "$d/.github/workflows/ci.yml" "$d/.github/workflows/ci.yaml"
run_case "workflow .yaml" "$d" 0 "${OK_CLAUDE}${nl}${OK_WF}${nl}${OK_GI}"

d="$WORKDIR/yml-dir"; make_ready "$d"; rm "$d/.github/workflows/ci.yml"; mkdir "$d/.github/workflows/ci.yml"
run_case "directory named *.yml" "$d" 1 "${OK_CLAUDE}${nl}${NG_WF}${nl}${OK_GI}"

d="$WORKDIR/no-gitignore"; make_ready "$d"; rm "$d/.gitignore"
run_case ".gitignore missing" "$d" 1 "${OK_CLAUDE}${nl}${OK_WF}${nl}${NG_GI}"

d="$WORKDIR/commented"; make_ready "$d"; printf '# .claude/settings.local.json\n' > "$d/.gitignore"
run_case ".gitignore entry commented out" "$d" 1 "${OK_CLAUDE}${nl}${OK_WF}${nl}${NG_GI}"

d="$WORKDIR/prefix"; make_ready "$d"; printf '.claude/settings.local.json.bak\n' > "$d/.gitignore"
run_case ".gitignore entry prefix only" "$d" 1 "${OK_CLAUDE}${nl}${OK_WF}${nl}${NG_GI}"

d="$WORKDIR/empty"; mkdir -p "$d"
run_case "empty dir" "$d" 1 "${NG_CLAUDE}${nl}${NG_WF}${nl}${NG_GI}"

run_case "dir not found" "$WORKDIR/does-not-exist" 2 ""

if [ -e "$GH_LOG" ]; then
  fail=$((fail + 1))
  echo "FAIL GitHub CLI was called: $(cat "$GH_LOG")"
else
  pass=$((pass + 1))
fi

echo "new-project: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
