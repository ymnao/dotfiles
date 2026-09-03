#!/usr/bin/env bash
set -euo pipefail

# Dependabot PR 一覧 JSON (stdin) を semver / ecosystem / security で分類して
# JSON 配列として出力する。
#
# 呼び出し側 (SKILL.md) が gh を直接叩き、その出力を stdin で渡す構造。
# 理由: bash → gh のネストは macOS Keychain 認証が切れる (memory
# feedback_skill_gh_no_nested と gather-branch-info.sh 冒頭コメント参照)。
#
# 入力: gh pr list --author app/dependabot --state open --json number,title,headRefName,url,body,labels
# 出力: 各 PR に semver / ecosystem / security を付与した JSON 配列
#
# 分類は保守側に倒す方針: 判別できない (grouped PR / 非標準 title / pre-release)
# は semver=unknown → SKILL.md 側で「個別維持」扱いに落とす。breaking_hint 検出は
# substring match が false-positive を量産するため廃止し、「major は人間判断」の
# 一点に絞る (issue #105 の「安全性の depth」節)。

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is not installed" >&2
  exit 1
fi

# ecosystem 判定: dependabot が付ける headRefName の prefix を使う
classify_ecosystem() {
  case "$1" in
    dependabot/github_actions/*) printf 'github-actions' ;;
    dependabot/npm_and_yarn/*)   printf 'npm' ;;
    dependabot/uv/*)             printf 'uv' ;;
    *)                           printf 'unknown' ;;
  esac
}

# grouped PR 判定: dependabot.yml の groups 機能で複数依存を 1 PR にまとめた
# ケース。title は 'Bumps the <name> group with N updates: bumps A ... and B ...'
# のような形式で from/to が複数入るため semver 単一 pair 判定は不能。
# is_grouped が真なら classify_semver は unknown に倒す。
is_grouped() {
  case "$1" in
    *"the "*" group with "*|*" and bumps "*|*" and updates "*) return 0 ;;
  esac
  return 1
}

# commit-message prefix 正規化: dependabot.yml の commit-message 設定
# (prefix / include: scope) で title 冒頭に 'Chore(deps): ' 等の
# conventional-commit prefix が付くケース (issue #266)。単一の
# '<token>(<scope>)?: ' だけを 1 回剥がす (anchored・非 global)。
#
# 受理を conventional-commit 形に限定するのは fail-closed 方針の維持のため。
# 多段 prefix ('a(x): b: Bump ...')・空白入り token ('Update readme: ')・
# colon 直後に空白なし ('chore:Bump')・空 prefix (': Bump') は剥がさず、
# 後段の semver regex 不一致で unknown に倒れる。
#
# 逆に 'Note: Bump evil from 1.0.0 to 9.9.9' のような人間が書いた title は
# この形にマッチするため受理される。title だけでは Dependabot 生成物と弁別
# できないので、実質のガードは呼び出し側 (SKILL.md) が
# `gh pr list --author app/dependabot` で入力を絞っていること。
strip_commit_prefix() {
  printf '%s' "$1" | sed -E 's/^[A-Za-z][A-Za-z0-9_-]*(\([^()]*\))?: +//'
}

# semver 判定: prefix を剥がした title に anchor した
# 'Bump[s]? <pkg> from [v]X.Y[.Z] to [v]A.B[.C]' パターンで from/to を抜く。
# v prefix (v4.1.1) を許容。grouped は先に unknown。
# パース不能は unknown → 統合しない扱いに倒す。
parse_version_pair() {
  local title
  title=$(strip_commit_prefix "$1")
  # 末尾は空白または EOL でバージョンを閉じる。'to 2.0.0-beta.1' のような
  # pre-release suffix を .* で吸って通常 major/minor/patch と誤分類しないよう、
  # to 側の trailing .* を ( .*)?$ に置換して境界を明示する。
  # 区切りは `|`。両辺とも数字とドットだけの regex で取るので値に混ざらない
  printf '%s' "$title" | sed -nE 's/^[Bb]ump[s]? +[^ ]+ +from +v?([0-9]+\.[0-9]+(\.[0-9]+)?) +to +v?([0-9]+\.[0-9]+(\.[0-9]+)?)( .*)?$/\1|\3/p'
}

# ターゲットバージョン: SKILL.md step 7 が `pnpm up <pkg>@<Y>` に渡す値。
# 分類にしか使わない from と違い、この値はコマンド引数として外に出るので
# **regex が検証した部分文字列そのもの**を出力に載せる。agent が生 title から
# 転記する形にすると、検証した文字列と実際に使う文字列が別物になる。
extract_to_version() {
  local pair
  if is_grouped "$1"; then
    printf ''
    return
  fi
  pair=$(parse_version_pair "$1")
  printf '%s' "${pair##*|}"
}

classify_semver() {
  local pair from to fmaj fmin tmaj tmin
  # grouped 判定は prefix 剥がし前の生 title で行う (substring 判定なので
  # prefix の有無に影響されない。テストで prefix + grouped を pin 済み)
  if is_grouped "$1"; then
    printf 'unknown'
    return
  fi
  pair=$(parse_version_pair "$1")
  from=${pair%%|*}
  to=${pair##*|}
  if [ -z "$from" ] || [ -z "$to" ]; then
    printf 'unknown'
    return
  fi
  fmaj=$(printf '%s' "$from" | cut -d. -f1)
  fmin=$(printf '%s' "$from" | cut -d. -f2)
  tmaj=$(printf '%s' "$to"   | cut -d. -f1)
  tmin=$(printf '%s' "$to"   | cut -d. -f2)
  if [ "$fmaj" != "$tmaj" ]; then
    printf 'major'
  elif [ "$fmin" != "$tmin" ]; then
    printf 'minor'
  else
    printf 'patch'
  fi
}

# security 判定: false-positive を避けるため厳密なパターンに絞る。
# - body: GHSA-<4>-<4>-<4> の GitHub Security Advisory ID 実体 (英数ハイフンで
#   'GitHub Security Advisory Database' などの定型文言は拾わない)
# - labels: 改行区切りで渡された各ラベル名を case で完全一致判定
#   (comma-separated だと 'foo,security' のようなラベル名自身にカンマを含む
#   ケースで exact match 誤検出になるため \n-separated に切り替え)
# grep -qE を pipeline 末尾に置くと SIGPIPE で pipefail が発火する場合がある
# ため、here-string で pipeline を作らない
is_security() {
  local body="$1" labels="$2" line
  # GHSA-ID は英数 4-4-4。前後に英数字が続くと過長で無効なので境界を明示
  # (\b は BSD/GNU 差があるため [^a-z0-9] と行頭/行末で挟む)。
  if grep -qE '(^|[^a-z0-9])GHSA-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}([^a-z0-9]|$)' <<<"$body"; then
    printf 'true'
    return
  fi
  while IFS= read -r line; do
    case "$line" in
      security|Security|vulnerability|Vulnerability) printf 'true'; return ;;
    esac
  done <<<"$labels"
  printf 'false'
}

# パッケージ名: prefix を剥がした title の 'Bump[s]? <pkg> from ...' から抜く。
# classify_semver と同じ strip_commit_prefix を経由するのは、両者が
# 「commit-message prefix を読み飛ばした後の Dependabot 生成 title を読む」
# という同じ問いに答えているため。個別に regex へ埋め込むと drift し、
# 「semver は unknown なのに package だけ取れる」不整合が構造的に起こりうる。
# 受理する package 名: npm の名前 (`lodash` / `@scope/pkg`) と GitHub Actions の
# `owner/repo`。segment は英数始まりで、以降は `._~-` のみ許す。`@` は先頭の
# scope prefix 位置にしか置けないので `name@npm:other` / `name@https://...` は
# 落ちる。bash 3.2 の `[[ =~ ]]` で使うため変数に置く (リテラル埋め込みは
# 3.2 でクォート規則が版依存になる)
PACKAGE_NAME_RE='^@?[A-Za-z0-9][A-Za-z0-9._~-]*(/[A-Za-z0-9][A-Za-z0-9._~-]*)?$'

extract_package() {
  strip_commit_prefix "$1" | sed -nE 's/^[Bb]ump[s]? +([^ ]+) +from .*/\1/p'
}

# 入力を先に検証してから処理する。壊れた JSON / 非配列 root で
# `jq -c '.[]' | while | jq -s '.'` の pipeline 末尾が空配列 [] を吐いてしまい
# 「エラー時 stdout empty」の契約を破る問題を回避するため、input を buffer して
# array 型チェックを通してから stream 処理に渡す。
INPUT=$(cat)
if ! printf '%s' "$INPUT" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "ERROR: input is not a JSON array" >&2
  exit 1
fi

# 各 PR を classify して JSON 配列にまとめる。
# 1 PR = 1 JSON object を stream し per-PR で jq -r 抽出する (fork は 6N 程度に
# 増えるが N は Dependabot open PR 数で通常 5-10、レイテンシは無視できる)。
# ENTRY を stdout に流し末尾で jq -s '.' で配列にまとめる (O(N²) 累積は回避)。
printf '%s' "$INPUT" | jq -c '.[]' \
  | while read -r pr_json; do
      NUMBER=$(printf '%s' "$pr_json" | jq -r '.number')
      TITLE=$(printf '%s'  "$pr_json" | jq -r '.title')
      HEAD=$(printf '%s'   "$pr_json" | jq -r '.headRefName')
      URL=$(printf '%s'    "$pr_json" | jq -r '.url')
      BODY=$(printf '%s'   "$pr_json" | jq -r '.body // ""')
      # ラベル名は 1 行 1 個で is_security に渡す (ラベル名自身にカンマを含む
      # ケースで exact match が破綻しないよう、区切り文字を改行にする)
      LABELS=$(printf '%s' "$pr_json" | jq -r '.labels[]?.name')

      ECOSYSTEM=$(classify_ecosystem "$HEAD")
      SEMVER=$(classify_semver "$TITLE")
      SECURITY=$(is_security "$BODY" "$LABELS")
      PACKAGE=$(extract_package "$TITLE")
      TO_VERSION=$(extract_to_version "$TITLE")

      # package 名は blacklist ではなく whitelist で受ける。`pnpm up <spec>` の
      # 引数は「名前」ではなく **依存 spec 全体**として解釈されるので、shell の
      # 再スキャンを経なくても title の編集だけで別物を入れられる (2026-09-02 実測:
      # `pnpm up 'secretlint@npm:left-pad@1.3.0'` は package.json の secretlint を
      # 別 package の alias に置換して exit 0、`'*@1.0.1'` は全依存を書き換え、
      # `'foo@https://host/x.tgz'` は当該ホストへ resolve しにいく)。
      # extract_package の `[^ ]+` はこれらを全部通すため、npm 名 / GitHub Actions
      # の `owner/repo` に一致しないものは unknown に倒して SKILL.md step 4 の
      # 「個別維持」へ落とす。改行を含む title もここで落ちる (`=~` は行単位では
      # なく文字列全体に anchor するため)
      if ! [[ "$PACKAGE" =~ $PACKAGE_NAME_RE ]]; then
        PACKAGE=''
        TO_VERSION=''
        SEMVER='unknown'
      fi

      jq -n \
        --argjson number "$NUMBER" \
        --arg title "$TITLE" \
        --arg headRefName "$HEAD" \
        --arg url "$URL" \
        --arg package "$PACKAGE" \
        --arg toVersion "$TO_VERSION" \
        --arg ecosystem "$ECOSYSTEM" \
        --arg semver "$SEMVER" \
        --argjson security "$SECURITY" \
        '{number: $number, title: $title, headRefName: $headRefName, url: $url, package: $package, toVersion: $toVersion, ecosystem: $ecosystem, semver: $semver, security: $security}'
    done \
  | jq -s '.'
