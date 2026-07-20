#!/usr/bin/env bash
#
# PreToolUse hook (Claude Code / Codex CLI 共通): `gh pr create` の実行前に
# (1) HEAD コミットの CI が green か、(2) PR body に fix-or-issue-or-dismiss ポリシー違反
# (「defer(未起票)」marker) が残っていないか、の 2 点を検証する
# 正本: agents/hooks/verify-ci-before-pr.sh
# (claude/hooks/ と codex/hooks/ からは相対 symlink で参照される)
#
# - 対象コミット: git HEAD
# - bypass: --draft/-d(falsy 値 --draft=false 等は bypass しない)、.github/workflows/ 空、GitHub 以外の remote、ツール不在
# - 状態判定: GitHub GraphQL の statusCheckRollup.state（legacy status + checks 統合）
# - exit 0 = 許可, exit 2 = block (stderr 文字列が Claude にフィードバックされる)
#
# 設計メモ:
#   Claude Code sandbox の excludedCommands は top-level の Bash コマンドにしか適用されず、
#   hook 内から gh の HTTP API を直叩きすると macOS Keychain アクセスが遮断され
#   TLS 検証エラー (OSStatus -26276) で死ぬ。回避のため
#   gh auth token (Keychain READ は通る) で token 取得 → curl で API 直叩きに統一する。
#

set -uo pipefail
shopt -s nullglob

input=$(cat)

# 早期 short-circuit: 入力に gh/pr/create が揃わなければ即終了。
# 99% の Bash 呼び出しはここで落ちて jq fork を回避する。
case "$input" in
  *gh*pr*create*) ;;
  *) exit 0 ;;
esac

for tool in jq gh git curl; do
  command -v "$tool" &>/dev/null || exit 0
done

command=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty')
[[ -z "$command" ]] && exit 0

# command 位置 (start, または `;`/`&&`/`||`/`|`/`(`/`{`/backtick/space/`/`(パス区切り)/`\` の直後)
# にある `gh pr create` のみマッチ。`[^;&|]*` で sub-command 境界を超えない。
gh_segment=$(printf '%s\n' "$command" \
  | grep -oE '(^|[;&|({`[:space:]/\])([A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*[[:space:]]+)*gh[[:space:]]+pr[[:space:]]+create[^;&|]*' \
  | head -1 || true)
[[ -z "$gh_segment" ]] && exit 0

# --draft / -d は WIP 用 bypass (falsy 値 --draft=false 等は bypass しない)
if printf '%s\n' "$gh_segment" | grep -qE '([[:space:]]|^)(--draft(=([Tt][Rr][Uu][Ee]|[Tt]|1))?|-d)([[:space:]]|$)'; then
  exit 0
fi

# fix-or-issue-or-dismiss ポリシー検査 (pr skill 参照): PR body に「defer(未起票)」が
# 残ったままの normal PR 作成をブロックする。finding は「fix 済み」か
# 「issue URL 起票済み」のどちらかでなければならない (draft は上で bypass 済み)。
# --body-file <path> / --body-file=<path> の両形式からファイルを解決し、
# inline --body 内のマーカーは gh_segment 自体の文字列検査で拾う。
DEFER_MARKER="defer(未起票)"
# フラグ値の抽出 helper: 「double quote 囲み (スペース可)」→「single quote
# 囲み (スペース可)」→「裸トークン」の順に試す。先頭の [[:space:]] anchor で
# 他フラグの値内に現れた同名文字列への誤マッチを防ぐ。$1 は ERE alternation 可
# (例 '--body-file|-F')。flag 自体が group 1 になるため値は \4\5 / \3 で取る
# (値側 alternation は片方しかマッチしないため連結で常に一方だけが残る)。
extract_flag_value() {
  local flag="$1" v
  v=$(printf '%s\n' "$gh_segment" \
    | sed -nE 's/.*[[:space:]]('"$flag"')(=|[[:space:]]+)("([^"]*)"|([^[:space:]]+)).*/\4\5/p')
  if [[ -z "$v" || "$v" == \'* ]]; then
    v=$(printf '%s\n' "$gh_segment" \
      | sed -nE "s/.*[[:space:]]($flag)(=|[[:space:]]+)'([^']*)'.*/\\3/p")
  fi
  printf '%s' "$v"
}
# 短縮エイリアス (-F = --body-file, -b = --body) も対象にする (迂回防止)
body_file=$(extract_flag_value '--body-file|-F')
defer_found=""
if [[ -n "$body_file" || $gh_segment == *--body-file* ]] \
  || printf '%s\n' "$gh_segment" | grep -qE '[[:space:]]-F([[:space:]=]|$)'; then
  # --body-file 指定時は fail-closed: stdin (`-`)・変数展開 (`"$TMPDIR/x.md"`)・
  # 存在しない相対パス等、hook から通常ファイルとして解決できない形式は
  # 検査不能 = defer 検査の迂回経路になるためブロックする (この hook の他の
  # 経路は fail-open だが、ここはポリシー強制が目的なので方針を変える)
  if [[ -z "$body_file" || "$body_file" == "-" || ! -f "$body_file" || ! -r "$body_file" ]]; then
    cat >&2 <<EOF
[verify-ci-before-pr] --body-file の値を検査可能な実ファイルとして解決できません (got: '${body_file:-<未解決>}')。
fix-or-issue-or-dismiss ポリシー検査のため、変数展開や stdin (-) ではなくリテラルの実ファイルパスで渡してください。
WIP として進めたい場合は --draft を付ければスキップします。
EOF
    exit 2
  fi
  # `grep -- `: `-` 始まりのファイル名がオプション解釈されるのを防ぐ
  if grep -qF -- "$DEFER_MARKER" "$body_file"; then
    defer_found="body-file: $body_file"
  fi
else
  # inline --body の値のみ検査する (gh_segment 全体を grep すると --title 等の
  # 値に marker 文字列が含まれるだけで false positive block になるため)。
  # 比較は pure bash: printf | grep だと pipefail 下で producer の SIGPIPE が
  # 判定を壊す理論経路があり、fork も不要になる。
  # 既知の限界: (1) 実際の --body より前に置かれた他フラグの引用値内に
  # 「 --body <marker>」文字列が含まれると誤 block する (シェル語彙解析なしの
  # 正規表現抽出の限界。--draft で回避可能な保守的 false positive として受容)。
  # (2) `--body "$(cat x)"` 等の動的展開値は文字列としてしか見えず fail-open
  # だが、動的展開を含む書き込み系コマンドは block-dangerous-commands hook が
  # 先にブロックするため、実質その hook が防御線になる
  body_value=$(extract_flag_value '--body|-b')
  if [[ -n "$body_value" && "$body_value" == *"$DEFER_MARKER"* ]]; then
    defer_found="--body inline"
  fi
fi
if [[ -n "$defer_found" ]]; then
  cat >&2 <<EOF
[verify-ci-before-pr] PR body に「$DEFER_MARKER」が含まれています ($defer_found)。
fix-or-issue-or-dismiss ポリシー: 未 fix の finding は (b) gh issue create で起票して URL を記載するか、
(c) 対応しない と判断して user 承認済みの「追跡しない (user 指示: <要約>)」書式に置き換えてください。
WIP として進めたい場合は --draft を付ければスキップします。
EOF
  exit 2
fi

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

workflows=( "$repo_root/.github/workflows/"*.yml "$repo_root/.github/workflows/"*.yaml )
[[ ${#workflows[@]} -eq 0 ]] && exit 0

# 解決順: @{upstream} の remote → origin → 任意の github.com remote。
# origin 固定だと upstream のみ・複数 remote のリポで誤って skip するため。
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
# bash =~ は POSIX ERE で non-greedy 不可なので、末尾を整理してから greedy match する
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

# 1 回の jq で state / pending check 名 / failed check 名 を TSV 抽出。
# commit が origin に未到達なら "MISSING" marker を返す。
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

# タブ区切りの分解はパラメータ展開で行う。IFS=$'\t' read はタブが空白系
# IFS のため連続タブ (空フィールド) を潰し、pending が空のとき failed の
# 内容が pending 側にずれるバグがあった。cut -f もタブ空フィールドは
# 保持するが、check 名に改行が混入した場合 (jq `-r` は改行を raw 出力)
# parsed が多行化し cut -f1 が "FAILURE\nname2" を返して case が
# default に落ち fail-open する退行があるため、パラメータ展開で先頭行
# だけを取り出してから 3 分割する。
first_line=${parsed%%$'\n'*}
state=${first_line%%$'\t'*}
rest=${first_line#*$'\t'}
pending=${rest%%$'\t'*}
failed=${rest#*$'\t'}

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
    # workflow ファイルは存在するが HEAD に対する check が無いケース。
    # 例: on: pull_request のみ（PR 作成後にトリガー）、path-filtered で対象外、
    # 反映待ち。これらは正常状態なので block せず情報出力のみ。
    cat >&2 <<EOF
[verify-ci-before-pr] HEAD ($head_sha) に紐づく check は見つかりませんでした。
on: pull_request のみ・path フィルタ・反映待ちなどのケースを想定して許可します。
EOF
    exit 0
    ;;
esac
