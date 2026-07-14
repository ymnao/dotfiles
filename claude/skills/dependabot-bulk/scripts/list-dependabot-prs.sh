#!/usr/bin/env bash
set -euo pipefail

# Dependabot PR 一覧 JSON (stdin) を semver / ecosystem / security / breaking-hint
# で分類して JSON 配列として出力する。
#
# 呼び出し側 (SKILL.md) が gh を直接叩き、その出力を stdin で渡す構造にしてある。
# 理由: bash → gh のネストは macOS Keychain 認証が切れる (memory
# feedback_skill_gh_no_nested と gather-branch-info.sh 冒頭コメント参照)。
#
# 入力: gh pr list --author app/dependabot --state open --json number,title,headRefName,url,body,labels
# 出力: 各 PR に semver / ecosystem / security / breaking_hint を付与した JSON 配列

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is not installed" >&2
  exit 1
fi

INPUT=$(cat)

# 空配列や空入力は素直にそのまま返す (呼び出し側で件数 0 判定できる)
COUNT=$(printf '%s' "$INPUT" | jq 'length')
if [ "$COUNT" = "0" ]; then
  printf '[]\n'
  exit 0
fi

# ecosystem 判定: dependabot が付ける headRefName の prefix を使う
#   github_actions → github-actions
#   npm_and_yarn   → npm
#   その他は unknown (将来 ecosystem 追加時に手を入れる)
classify_ecosystem() {
  case "$1" in
    dependabot/github_actions/*) printf 'github-actions' ;;
    dependabot/npm_and_yarn/*)   printf 'npm' ;;
    dependabot/*)                printf 'unknown' ;;
    *)                           printf 'unknown' ;;
  esac
}

# semver 判定: PR title の "from X to Y" を正規表現でパース
#   例: "Bump actions/checkout from 4.1.1 to 4.2.0" → 4.1.1 → 4.2.0 → minor
# major が変われば major、minor だけなら minor、それ以外は patch
# パース不能 (pre-release / commit sha 等) は unknown → 安全側で「統合しない」扱いに倒せる
classify_semver() {
  local title="$1" from to fmaj fmin tmaj tmin
  # title から from/to を抜き出す (最初の "from X to Y" のみ)
  from=$(printf '%s' "$title" | sed -nE 's/.*from ([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/p')
  to=$(printf '%s' "$title" | sed -nE 's/.*to ([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/p')
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

# security 判定: PR body に GHSA リンクを含む or labels に security 系
is_security() {
  local body="$1" labels="$2"
  if printf '%s' "$body" | grep -qiE 'GHSA-[a-z0-9-]+'; then
    printf 'true'
    return
  fi
  if printf '%s' "$labels" | grep -qiE 'security|vulnerab'; then
    printf 'true'
    return
  fi
  printf 'false'
}

# breaking-hint: PR body に BREAK / breaking / deprecat を含むか (大文字小文字無視)
# 外部 fetch は一切しない。Dependabot が body に埋める release notes のみが対象
has_breaking_hint() {
  if printf '%s' "$1" | grep -qiE 'breaking|deprecat'; then
    printf 'true'
  else
    printf 'false'
  fi
}

# パッケージ名: PR title の "Bump <pkg> from ..." から抜く
extract_package() {
  printf '%s' "$1" | sed -nE 's/^[Bb]ump[s]? +([^ ]+) +from .*/\1/p'
}

# 各 PR を classify して JSON 配列にまとめる
OUT='[]'
i=0
while [ "$i" -lt "$COUNT" ]; do
  PR=$(printf '%s' "$INPUT" | jq ".[$i]")
  NUMBER=$(printf '%s' "$PR" | jq -r '.number')
  TITLE=$(printf '%s' "$PR" | jq -r '.title')
  HEAD=$(printf '%s' "$PR" | jq -r '.headRefName')
  URL=$(printf '%s' "$PR" | jq -r '.url')
  BODY=$(printf '%s' "$PR" | jq -r '.body // ""')
  LABELS=$(printf '%s' "$PR" | jq -r '[.labels[]?.name] | join(",")')

  ECOSYSTEM=$(classify_ecosystem "$HEAD")
  SEMVER=$(classify_semver "$TITLE")
  SECURITY=$(is_security "$BODY" "$LABELS")
  BREAKING=$(has_breaking_hint "$BODY")
  PACKAGE=$(extract_package "$TITLE")

  ENTRY=$(jq -n \
    --argjson number "$NUMBER" \
    --arg title "$TITLE" \
    --arg headRefName "$HEAD" \
    --arg url "$URL" \
    --arg package "$PACKAGE" \
    --arg ecosystem "$ECOSYSTEM" \
    --arg semver "$SEMVER" \
    --argjson security "$SECURITY" \
    --argjson breaking_hint "$BREAKING" \
    '{number: $number, title: $title, headRefName: $headRefName, url: $url, package: $package, ecosystem: $ecosystem, semver: $semver, security: $security, breaking_hint: $breaking_hint}')

  OUT=$(printf '%s' "$OUT" | jq --argjson e "$ENTRY" '. + [$e]')
  i=$((i + 1))
done

printf '%s\n' "$OUT"
