#!/usr/bin/env bash
#
# PreToolUse hook (Codex CLI): `gh pr create` の実行前に HEAD コミットの CI が green か検証する
#
# - 対象コミット: git HEAD
# - bypass: --draft/-d、.github/workflows/ 空、GitHub 以外の remote、ツール不在
# - 状態判定: GitHub GraphQL の statusCheckRollup.state
# - exit 0 = 許可, exit 2 = ブロック
#

set -uo pipefail
shopt -s nullglob

input=$(cat)

case "$input" in
  *gh*pr*create*) ;;
  *) exit 0 ;;
esac

for tool in jq gh git curl; do
  command -v "$tool" &>/dev/null || exit 0
done

command=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty')
[[ -z "$command" ]] && exit 0

gh_segment=$(printf '%s\n' "$command" \
  | grep -oE '(^|[;&|({`[:space:]])([A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*[[:space:]]+)*gh[[:space:]]+pr[[:space:]]+create[^;&|]*' \
  | head -1 || true)
[[ -z "$gh_segment" ]] && exit 0

if printf '%s\n' "$gh_segment" | grep -qE '([[:space:]]|^)(--draft|-d)([[:space:]]|=|$)'; then
  exit 0
fi

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

workflows=( "$repo_root/.github/workflows/"*.yml "$repo_root/.github/workflows/"*.yaml )
[[ ${#workflows[@]} -eq 0 ]] && exit 0

resolve_github_remote_url() {
  local url upstream_full upstream_remote r
  upstream_full=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || true
  if [[ -n "$upstream_full" ]]; then
    upstream_remote="${upstream_full%%/*}"
    url=$(git remote get-url "$upstream_remote" 2>/dev/null) || true
    [[ "$url" == *github.com* ]] && { echo "$url"; return 0; }
  fi
  url=$(git remote get-url origin 2>/dev/null) || true
  [[ "$url" == *github.com* ]] && { echo "$url"; return 0; }
  for r in $(git remote 2>/dev/null); do
    url=$(git remote get-url "$r" 2>/dev/null) || true
    [[ "$url" == *github.com* ]] && { echo "$url"; return 0; }
  done
  return 1
}

remote_url=$(resolve_github_remote_url) || exit 0
remote_url="${remote_url%/}"
if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
  owner="${BASH_REMATCH[1]}"
  repo="${BASH_REMATCH[2]%.git}"
else
  exit 0
fi

head_sha=$(git rev-parse HEAD 2>/dev/null) || exit 0

token=$(gh auth token 2>/dev/null) || {
  echo "[verify-ci-before-pr] gh auth token 取得失敗: CI 検証をスキップします" >&2
  exit 0
}
[[ -z "$token" ]] && exit 0

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

parsed=$(printf '%s' "$result" | jq -r '
  .data.repository.object as $o
  | if $o == null then "MISSING\t\t"
    else
      ($o.statusCheckRollup.state // "NONE") as $state
      | [$o.checkSuites.nodes[].checkRuns.nodes[]] as $runs
      | ($runs | map(select(.status != "COMPLETED").name) | unique | join(", ")) as $pending
      | ($runs
          | map(select(.conclusion as $c | ["FAILURE","CANCELLED","TIMED_OUT","ACTION_REQUIRED","STARTUP_FAILURE"] | index($c)))
          | map("\(.name) (\(.conclusion))") | unique | join(", ")) as $failed
      | "\($state)\t\($pending)\t\($failed)"
    end' 2>/dev/null) || {
  echo "[verify-ci-before-pr] レスポンスパース失敗: CI 検証をスキップします" >&2
  exit 0
}

IFS=$'\t' read -r state pending failed <<<"$parsed"

case "$state" in
  MISSING)
    cat >&2 <<EOF
[verify-ci-before-pr] HEAD ($head_sha) が origin/$owner/$repo に見つかりません。
まず \`git push\` してから \`gh pr create\` を実行してください。
EOF
    exit 2
    ;;
  SUCCESS)
    exit 0
    ;;
  PENDING|EXPECTED)
    cat >&2 <<EOF
[verify-ci-before-pr] CI 未完了 (state=$state)
進行中: ${pending:-(詳細不明)}
完走を待ってから \`gh pr create\` を再実行してください。
WIP として進めたい場合は --draft を付ければスキップします。
EOF
    exit 2
    ;;
  FAILURE|ERROR)
    cat >&2 <<EOF
[verify-ci-before-pr] CI 失敗 (state=$state)
失敗 check: ${failed:-(詳細不明)}
原因を修正・再 push してから PR を作成してください。
WIP として draft で開きたい場合は --draft を付ければスキップします。
EOF
    exit 2
    ;;
  *)
    cat >&2 <<EOF
[verify-ci-before-pr] HEAD ($head_sha) に紐づく check は見つかりませんでした。
on: pull_request のみ・path フィルタ・反映待ちなどのケースを想定して許可します。
EOF
    exit 0
    ;;
esac
