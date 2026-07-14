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

# semver 判定: title 冒頭に anchor した 'Bump[s]? <pkg> from [v]X.Y[.Z] to [v]A.B[.C]'
# パターンで from/to を抜く。v prefix (v4.1.1) を許容。grouped は先に unknown。
# パース不能は unknown → 統合しない扱いに倒す。
classify_semver() {
  local title="$1" from to fmaj fmin tmaj tmin
  if is_grouped "$title"; then
    printf 'unknown'
    return
  fi
  # 末尾は空白または EOL でバージョンを閉じる。'to 2.0.0-beta.1' のような
  # pre-release suffix を .* で吸って通常 major/minor/patch と誤分類しないよう、
  # to 側の trailing .* を ( .*)?$ に置換して境界を明示する。
  from=$(printf '%s' "$title" | sed -nE 's/^[Bb]ump[s]? +[^ ]+ +from +v?([0-9]+\.[0-9]+(\.[0-9]+)?) +to +v?[0-9]+\.[0-9]+(\.[0-9]+)?( .*)?$/\1/p')
  to=$(printf '%s' "$title"   | sed -nE 's/^[Bb]ump[s]? +[^ ]+ +from +v?[0-9]+\.[0-9]+(\.[0-9]+)? +to +v?([0-9]+\.[0-9]+(\.[0-9]+)?)( .*)?$/\2/p')
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
# - labels: comma-separated リストに 'security' / 'vulnerability' の exact match
is_security() {
  local body="$1" labels="$2"
  if printf '%s' "$body" | grep -qE 'GHSA-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}'; then
    printf 'true'
    return
  fi
  case ",$labels," in
    *,security,*|*,Security,*|*,vulnerability,*|*,Vulnerability,*) printf 'true'; return ;;
  esac
  printf 'false'
}

# パッケージ名: title の 'Bump[s]? <pkg> from ...' から抜く
extract_package() {
  printf '%s' "$1" | sed -nE 's/^[Bb]ump[s]? +([^ ]+) +from .*/\1/p'
}

# 各 PR を classify して JSON 配列にまとめる。
# @tsv 経由だと jq のエスケープ (\t, \n, \\) を read が解釈せず literal 混入する
# ため、1 PR = 1 JSON object を stream し per-PR で jq -r 抽出する。fork は 6N
# 程度に増えるが N は Dependabot open PR 数で通常 5-10、レイテンシは無視できる。
# ENTRY を stdout に流し末尾で jq -s '.' で配列にまとめる (O(N²) 累積は回避)。
jq -c '.[]' \
  | while read -r pr_json; do
      NUMBER=$(printf '%s' "$pr_json" | jq -r '.number')
      TITLE=$(printf '%s'  "$pr_json" | jq -r '.title')
      HEAD=$(printf '%s'   "$pr_json" | jq -r '.headRefName')
      URL=$(printf '%s'    "$pr_json" | jq -r '.url')
      BODY=$(printf '%s'   "$pr_json" | jq -r '.body // ""')
      LABELS=$(printf '%s' "$pr_json" | jq -r '[.labels[]?.name] | join(",")')

      ECOSYSTEM=$(classify_ecosystem "$HEAD")
      SEMVER=$(classify_semver "$TITLE")
      SECURITY=$(is_security "$BODY" "$LABELS")
      PACKAGE=$(extract_package "$TITLE")

      jq -n \
        --argjson number "$NUMBER" \
        --arg title "$TITLE" \
        --arg headRefName "$HEAD" \
        --arg url "$URL" \
        --arg package "$PACKAGE" \
        --arg ecosystem "$ECOSYSTEM" \
        --arg semver "$SEMVER" \
        --argjson security "$SECURITY" \
        '{number: $number, title: $title, headRefName: $headRefName, url: $url, package: $package, ecosystem: $ecosystem, semver: $semver, security: $security}'
    done \
  | jq -s '.'
