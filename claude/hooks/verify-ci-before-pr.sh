#!/usr/bin/env bash
#
# PreToolUse hook: `gh pr create` の実行前に HEAD コミットの CI が green か検証する
#
# - 対象コミット: git HEAD
# - bypass 条件: --draft/-d フラグ付き、.github/workflows/ が空、git 外、GitHub 以外の remote
# - 状態判定: GitHub GraphQL の statusCheckRollup.state（legacy status + checks 統合）
# - exit 0 = 許可, exit 2 = block (stderr 文字列が Claude にフィードバックされる)
#
# 設計メモ:
#   Claude Code sandbox の excludedCommands は top-level の Bash コマンドにしか適用されず、
#   hook 内から gh の HTTP API を直接叩くと macOS Keychain アクセスが遮断され
#   TLS 検証エラー (OSStatus -26276) で死ぬ。回避のため
#   gh auth token (Keychain READ は通る) で token 取得 → curl で API 呼び出しに統一する。
#

set -uo pipefail

input=$(cat)

# 必須ツールが無ければ fail-open
for tool in jq gh git curl; do
  command -v "$tool" &>/dev/null || exit 0
done

command=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty')
[[ -z "$command" ]] && exit 0

# --- 対象判定 ---
# command 位置 (start, または `;`/`&&`/`||`/`|`/`(`/`{`/backtick/space の直後)
# にある `gh pr create` のみマッチ。`[^;&|]*` で sub-command 境界を超えない。
gh_segment=$(printf '%s\n' "$command" \
  | grep -oE '(^|[;&|({`[:space:]])([A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*[[:space:]]+)*gh[[:space:]]+pr[[:space:]]+create[^;&|]*' \
  | head -1 || true)
[[ -z "$gh_segment" ]] && exit 0

# --draft / -d は skip（WIP は CI 落ちていても OK）
if printf '%s\n' "$gh_segment" | grep -qE '([[:space:]]|^)(--draft|-d)([[:space:]]|=|$)'; then
  exit 0
fi

# git repo 外
git rev-parse --is-inside-work-tree &>/dev/null || exit 0

# CI workflow が定義されているか
if ! find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | grep -q .; then
  exit 0
fi

# remote URL から owner/repo 抽出（gh repo view は sandbox で TLS 死するので使わない）
# bash =~ は POSIX ERE で non-greedy 不可なので、一旦末尾を整理してから greedy match する
remote_url=$(git remote get-url origin 2>/dev/null) || exit 0
remote_url="${remote_url%/}"
if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
  owner="${BASH_REMATCH[1]}"
  repo="${BASH_REMATCH[2]%.git}"
else
  # GitHub 以外の remote は対象外
  exit 0
fi

head_sha=$(git rev-parse HEAD 2>/dev/null) || exit 0

# gh auth token は Keychain READ のみで sandbox 内でも通る
token=$(gh auth token 2>/dev/null) || {
  echo "[verify-ci-before-pr] gh auth token 取得失敗: CI 検証をスキップします" >&2
  exit 0
}
[[ -z "$token" ]] && exit 0

# GraphQL を curl で叩く（curl は Secure Transport を使わない経路で TLS 通る）
query=$(jq -n --arg owner "$owner" --arg repo "$repo" --arg sha "$head_sha" '{
  query: "query($owner:String!,$repo:String!,$sha:GitObjectID!){repository(owner:$owner,name:$repo){object(oid:$sha){...on Commit{statusCheckRollup{state} checkSuites(first:30){nodes{checkRuns(first:50){nodes{name status conclusion}}}}}}}}",
  variables: { owner: $owner, repo: $repo, sha: $sha }
}')

result=$(curl -sS --max-time 15 \
  -H "Authorization: bearer $token" \
  -H "Accept: application/vnd.github+json" \
  -X POST -d "$query" \
  https://api.github.com/graphql 2>/dev/null) || {
  echo "[verify-ci-before-pr] GitHub API 呼び出し失敗: CI 検証をスキップします" >&2
  exit 0
}

obj=$(printf '%s' "$result" | jq -r '.data.repository.object // "null"' 2>/dev/null)
if [[ "$obj" == "null" ]]; then
  cat >&2 <<EOF
[verify-ci-before-pr] HEAD ($head_sha) が origin/$owner/$repo に見つかりません。
まず \`git push\` してから \`gh pr create\` を実行してください。
EOF
  exit 2
fi

state=$(printf '%s' "$result" | jq -r '.data.repository.object.statusCheckRollup.state // "NONE"' 2>/dev/null)

case "$state" in
  SUCCESS)
    exit 0
    ;;
  PENDING|EXPECTED)
    pending=$(printf '%s' "$result" | jq -r '
      [.data.repository.object.checkSuites.nodes[].checkRuns.nodes[]
       | select(.status != "COMPLETED") | .name] | unique | join(", ")' 2>/dev/null)
    cat >&2 <<EOF
[verify-ci-before-pr] CI 未完了 (state=$state)
進行中: ${pending:-(詳細不明)}
完走を待ってから \`gh pr create\` を再実行してください。
WIP として進めたい場合は --draft を付ければスキップします。
EOF
    exit 2
    ;;
  FAILURE|ERROR)
    failed=$(printf '%s' "$result" | jq -r '
      [.data.repository.object.checkSuites.nodes[].checkRuns.nodes[]
       | select(.conclusion as $c | ["FAILURE","CANCELLED","TIMED_OUT","ACTION_REQUIRED","STARTUP_FAILURE"] | index($c))
       | "\(.name) (\(.conclusion))"] | unique | join(", ")' 2>/dev/null)
    cat >&2 <<EOF
[verify-ci-before-pr] CI 失敗 (state=$state)
失敗 check: ${failed:-(詳細不明)}
原因を修正・再 push してから PR を作成してください。
WIP として draft で開きたい場合は --draft を付ければスキップします。
EOF
    exit 2
    ;;
  NONE|*)
    cat >&2 <<EOF
[verify-ci-before-pr] HEAD ($head_sha) に紐づく check が見つかりません。
.github/workflows/ は存在しますが、CI が未トリガー or 反映待ちの可能性。
数秒待ってから再実行するか、--draft でスキップしてください。
EOF
    exit 2
    ;;
esac
