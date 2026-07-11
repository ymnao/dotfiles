#!/usr/bin/env bash
# -e を外している: hook は block を exit 2 で表す正常仕様なので、
# run_hook_in のサブシェルで `|| rc=$?` により exit code を受ける。
# -e を追加すると block 経路 (ci-failure / ci-pending 等) でランナー
# 自身が死に、期待値 2 のケースを検証できなくなる。
set -uo pipefail

# 開発者環境の ~/.gitconfig (commit.gpgsign=true, core.hooksPath 等) が
# make_repo の初期コミットを spurious fail させないよう global/system
# config を切り離す。
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

# verify-ci-before-pr.sh の block 経路を含むシナリオテスト。
# 旧テスト (tests/hooks/verify-ci-early-exit.cases.jsonl) は非 git の一時
# ディレクトリで実行されるため git 解決に失敗した時点で fail-open し、
# exit 2 の全経路 (MISSING/PENDING/FAILURE) が構造的に検証不能だった。
# ここでは本物の git リポジトリ + GitHub remote 形式の origin を用意し、
# gh / curl を PATH 上のスタブに差し替えて GraphQL 応答を固定することで、
# draft bypass・非 bypass (--draft=false)・CI 状態別の block を検証する。
#
# 限界: スタブは GraphQL 応答を fixture で固定するため、実 GitHub API の
# レスポンス形状変更は検出できない (実 API 経路は運用中の実使用が検証)。
#
# 使い方: run-verify-ci-tests.sh
#   環境変数 HOOK_PATH で hook の場所を上書きできる
#   (デフォルト: <リポジトリルート>/claude/hooks/verify-ci-before-pr.sh)
#
# 依存: bash 3.2+ / jq / git (gh・curl は不要 — スタブを使う)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
HOOK="${HOOK_PATH:-$REPO_ROOT/claude/hooks/verify-ci-before-pr.sh}"

if [ ! -f "$HOOK" ]; then
  echo "ERROR: hook not found: $HOOK (HOOK_PATH で上書き可)" >&2
  exit 1
fi
for tool in jq git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool is required" >&2; exit 1; }
done

BASE="$(mktemp -d "${TMPDIR:-/tmp}/verify-ci-tests.XXXXXX")"
cleanup() { [ -n "${BASE:-}" ] && rm -rf "$BASE"; }
trap cleanup EXIT

# --- gh / curl スタブ ---------------------------------------------------
# gh: `gh auth token` のみ成功しダミートークンを返す
mkdir -p "$BASE/bin"
cat >"$BASE/bin/gh" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "auth" ] && [ "${2:-}" = "token" ]; then
  echo stub-token
  exit 0
fi
exit 1
EOF
# curl: 引数を検証してから VERIFY_CI_FIXTURE の内容を返す。
# hook が Authorization header・testowner/testrepo を含む GraphQL body を
# 正しく送っていることを assert する (誤 endpoint・auth 抜けの退行検出)。
cat >"$BASE/bin/curl" <<'EOF'
#!/bin/sh
args="$*"
case "$args" in
  *"Authorization: bearer stub-token"*) ;;
  *) echo "curl stub: missing/wrong Authorization header: $args" >&2; exit 90 ;;
esac
case "$args" in
  *"api.github.com/graphql"*) ;;
  *) echo "curl stub: unexpected endpoint: $args" >&2; exit 91 ;;
esac
case "$args" in
  *testowner*) ;;
  *) echo "curl stub: GraphQL body missing owner=testowner: $args" >&2; exit 92 ;;
esac
case "$args" in
  *testrepo*) ;;
  *) echo "curl stub: GraphQL body missing repo=testrepo: $args" >&2; exit 92 ;;
esac
if [ -n "${VERIFY_CI_FIXTURE:-}" ] && [ -f "$VERIFY_CI_FIXTURE" ]; then
  cat "$VERIFY_CI_FIXTURE"
  exit 0
fi
exit 22
EOF
chmod +x "$BASE/bin/gh" "$BASE/bin/curl"

# --- GraphQL 応答 fixture -----------------------------------------------
mkdir -p "$BASE/fixtures"
cat >"$BASE/fixtures/success.json" <<'EOF'
{"data":{"repository":{"object":{"statusCheckRollup":{"state":"SUCCESS"},"checkSuites":{"nodes":[{"checkRuns":{"nodes":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]}}]}}}}}
EOF
cat >"$BASE/fixtures/failure.json" <<'EOF'
{"data":{"repository":{"object":{"statusCheckRollup":{"state":"FAILURE"},"checkSuites":{"nodes":[{"checkRuns":{"nodes":[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]}}]}}}}}
EOF
cat >"$BASE/fixtures/pending.json" <<'EOF'
{"data":{"repository":{"object":{"statusCheckRollup":{"state":"PENDING"},"checkSuites":{"nodes":[{"checkRuns":{"nodes":[{"name":"ci","status":"IN_PROGRESS","conclusion":null}]}}]}}}}}
EOF
cat >"$BASE/fixtures/missing.json" <<'EOF'
{"data":{"repository":{"object":null}}}
EOF

# --- テスト用リポジトリ ---------------------------------------------------
# $1=名前, $2=remote URL ("" なら remote なし), $3=workflows を作るか (yes/no)
make_repo() {
  local dir="$BASE/$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "test"
  printf 'x\n' >"$dir/f.txt"
  git -C "$dir" add -A
  git -C "$dir" commit -qm init
  [ -n "$2" ] && git -C "$dir" remote add origin "$2"
  if [ "$3" = "yes" ]; then
    mkdir -p "$dir/.github/workflows"
    printf 'name: ci\n' >"$dir/.github/workflows/ci.yml"
  fi
  printf '%s' "$dir"
}

GH_REPO=$(make_repo gh-repo "https://github.com/testowner/testrepo.git" yes)
NO_WF_REPO=$(make_repo no-wf "https://github.com/testowner/testrepo.git" no)
NON_GH_REPO=$(make_repo non-gh "https://gitlab.com/o/r.git" yes)

pass=0
fail=0

# $1=cwd, $2=fixture 名 ("" なら未設定), $3=command。exit code を echo
run_hook_in() {
  local json rc=0 fixture_env=""
  [ -n "$2" ] && fixture_env="$BASE/fixtures/$2.json"
  json=$(jq -cn --arg c "$3" '{"tool_input":{"command":$c}}')
  printf '%s' "$json" \
    | (cd "$1" && PATH="$BASE/bin:$PATH" VERIFY_CI_FIXTURE="$fixture_env" bash "$HOOK" >/dev/null 2>&1) || rc=$?
  printf '%s' "$rc"
}

check() {
  # $1=名前, $2=期待 exit, $3=実際
  if [ "$3" = "$2" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $1: expected=$2 got=$3"
    fail=$((fail + 1))
  fi
}

# 早期 exit 経路 (bypass / 対象外)。あえて failure fixture を渡すことで、
# bypass 判定が退行して API 到達経路へ落ちた場合に curl スタブが失敗
# JSON を返し hook が exit 2 → テスト FAIL となる (退行検出可)。
# fixture 未設定だと curl スタブが exit 22 → hook が fail-open (exit 0) し、
# 期待値と一致するため退行が検出できない (finding: bypass regression 不可視化)。
check "non-pr-command"   0 "$(run_hook_in "$GH_REPO" failure 'git status')"
check "gh-pr-list"       0 "$(run_hook_in "$GH_REPO" failure 'gh pr list')"
check "draft-bypass"     0 "$(run_hook_in "$GH_REPO" failure 'gh pr create --draft --title t --body b')"
check "draft-d-bypass"   0 "$(run_hook_in "$GH_REPO" failure 'gh pr create -d --title t')"
check "no-workflows"     0 "$(run_hook_in "$NO_WF_REPO" failure 'gh pr create --title t --body b')"
check "non-github"       0 "$(run_hook_in "$NON_GH_REPO" failure 'gh pr create --title t --body b')"

# API 到達経路 (fixture で CI 状態を固定)
check "ci-success"       0 "$(run_hook_in "$GH_REPO" success 'gh pr create --title t --body b')"
check "ci-failure"       2 "$(run_hook_in "$GH_REPO" failure 'gh pr create --title t --body b')"
check "ci-pending"       2 "$(run_hook_in "$GH_REPO" pending 'gh pr create --title t --body b')"
check "commit-missing"   2 "$(run_hook_in "$GH_REPO" missing 'gh pr create --title t --body b')"

# --draft=false は bypass しない (draft 判定の退行検出。CI 失敗なら block)
check "draft-false-no-bypass" 2 "$(run_hook_in "$GH_REPO" failure 'gh pr create --draft=false --title t')"

# ブロック時の stderr に失敗 check 名が含まれる (フィードバック契約)。
# IFS=$'\t' read の空フィールド潰れ (pending 空のとき failed が pending 側に
# ずれて「詳細不明」になる) の回帰検出を兼ねる。
json=$(jq -cn '{"tool_input":{"command":"gh pr create --title t --body b"}}')
stderr_out=$(printf '%s' "$json" \
  | (cd "$GH_REPO" && PATH="$BASE/bin:$PATH" VERIFY_CI_FIXTURE="$BASE/fixtures/failure.json" bash "$HOOK" 2>&1 >/dev/null)) || true
if printf '%s' "$stderr_out" | grep -q "ci (FAILURE)"; then
  pass=$((pass + 1))
else
  echo "FAIL stderr-failed-check-names: 失敗 check 名が stderr に含まれない"
  fail=$((fail + 1))
fi

# PENDING ブロック時の stderr に進行中 check 名が含まれる
stderr_out=$(printf '%s' "$json" \
  | (cd "$GH_REPO" && PATH="$BASE/bin:$PATH" VERIFY_CI_FIXTURE="$BASE/fixtures/pending.json" bash "$HOOK" 2>&1 >/dev/null)) || true
if printf '%s' "$stderr_out" | grep -q "進行中: ci"; then
  pass=$((pass + 1))
else
  echo "FAIL stderr-pending-check-names: 進行中 check 名が stderr に含まれない"
  fail=$((fail + 1))
fi

echo "----"
echo "verify-ci tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
