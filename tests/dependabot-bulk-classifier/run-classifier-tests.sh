#!/usr/bin/env bash
set -euo pipefail

# list-dependabot-prs.sh の決定的テスト。
# fixture JSON を stdin に流し、jq で個別 PR の分類結果 (ecosystem / semver /
# security / package) を assert する。
# CLASSIFIER 環境変数で script path を上書き可能。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
CLASSIFIER="${CLASSIFIER:-$REPO_ROOT/claude/skills/dependabot-bulk/scripts/list-dependabot-prs.sh}"

if [ ! -f "$CLASSIFIER" ]; then
  echo "ERROR: classifier not found: $CLASSIFIER" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq not installed" >&2
  exit 1
fi

pass=0
fail=0

# assert_field <name> <input JSON> <jq filter> <expected>
assert_field() {
  local name="$1" input="$2" filter="$3" want="$4" got
  got=$(printf '%s' "$input" | bash "$CLASSIFIER" | jq -r "$filter")
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $name (want=$want got=$got)" >&2
  fi
}

# assert_exit <name> <input> <expected> — expected は "0" または "nonzero"
# 非 0 終了時は stdout が空 (partial JSON を残さない) ことを厳密に確認する
assert_exit() {
  local name="$1" input="$2" want="$3" got_exit stdout
  set +e
  stdout=$(printf '%s' "$input" | bash "$CLASSIFIER" 2>/dev/null)
  got_exit=$?
  set -e
  case "$want" in
    0)       [ "$got_exit" = "0" ] || { fail=$((fail + 1)); echo "FAIL: $name want=0 got=$got_exit" >&2; return; } ;;
    nonzero) [ "$got_exit" != "0" ] || { fail=$((fail + 1)); echo "FAIL: $name want=nonzero got=0" >&2; return; } ;;
    *)       fail=$((fail + 1)); echo "FAIL: $name invalid want=$want" >&2; return ;;
  esac
  if [ "$want" = "nonzero" ] && [ -n "$stdout" ]; then
    fail=$((fail + 1))
    echo "FAIL: $name stdout not empty on error (got $(printf '%s' "$stdout" | head -c 80))" >&2
    return
  fi
  pass=$((pass + 1))
}

# ---- ecosystem (F2) ----
ECO_JSON='[
  {"number":1,"title":"Bump a from 1.0.0 to 1.0.1","headRefName":"dependabot/github_actions/a-1.0.1","url":"u","body":"","labels":[]},
  {"number":2,"title":"Bump b from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/b-1.0.1","url":"u","body":"","labels":[]},
  {"number":3,"title":"Bump c from 1.0.0 to 1.0.1","headRefName":"dependabot/bundler/c-1.0.1","url":"u","body":"","labels":[]},
  {"number":4,"title":"Bump d from 1.0.0 to 1.0.1","headRefName":"random/branch","url":"u","body":"","labels":[]},
  {"number":5,"title":"Bump e from 1.0.0 to 1.0.1","headRefName":"dependabot/uv/e-1.0.1","url":"u","body":"","labels":[]}
]'
assert_field "ecosystem: github_actions"  "$ECO_JSON" '.[0].ecosystem' 'github-actions'
assert_field "ecosystem: npm_and_yarn"    "$ECO_JSON" '.[1].ecosystem' 'npm'
assert_field "ecosystem: other dependabot"    "$ECO_JSON" '.[2].ecosystem' 'unknown'
assert_field "ecosystem: non-dependabot"      "$ECO_JSON" '.[3].ecosystem' 'unknown'
assert_field "ecosystem: uv"                  "$ECO_JSON" '.[4].ecosystem' 'uv'

# ---- semver: major/minor/patch/unknown 各分岐 (F4) ----
SEMVER_JSON='[
  {"number":1,"title":"Bump foo from 1.0.0 to 2.0.0","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":"","labels":[]},
  {"number":2,"title":"Bump foo from 1.0.0 to 1.1.0","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":"","labels":[]},
  {"number":3,"title":"Bump foo from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":"","labels":[]},
  {"number":4,"title":"Bump foo from 1.0 to 1.1","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":"","labels":[]},
  {"number":5,"title":"Bump foo from v4.1.1 to v4.2.0","headRefName":"dependabot/github_actions/foo","url":"u","body":"","labels":[]},
  {"number":6,"title":"Bump foo from 1.0.0 to 2.0.0-beta.1","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":"","labels":[]},
  {"number":7,"title":"Bump foo from 1.0.0-rc1 to 1.0.0","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":"","labels":[]},
  {"number":8,"title":"Random title with no version","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":"","labels":[]},
  {"number":9,"title":"Bump foo from 1.0.0 to 1.0.1 in /path","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":"","labels":[]}
]'
assert_field "semver: major"         "$SEMVER_JSON" '.[0].semver' 'major'
assert_field "semver: minor"         "$SEMVER_JSON" '.[1].semver' 'minor'
assert_field "semver: patch"         "$SEMVER_JSON" '.[2].semver' 'patch'
assert_field "semver: 2-part minor"  "$SEMVER_JSON" '.[3].semver' 'minor'
assert_field "semver: v prefix (F4)" "$SEMVER_JSON" '.[4].semver' 'minor'
assert_field "semver: pre-release to (F1)"    "$SEMVER_JSON" '.[5].semver' 'unknown'
assert_field "semver: pre-release from"       "$SEMVER_JSON" '.[6].semver' 'unknown'
assert_field "semver: no version"    "$SEMVER_JSON" '.[7].semver' 'unknown'
assert_field "semver: trailing path" "$SEMVER_JSON" '.[8].semver' 'patch'

# ---- toVersion: SKILL.md step 7 が pnpm up に渡す値 (issue #330) ----
# regex が検証した部分文字列そのものを出力に載せる契約。agent が生 title から
# 転記すると検証した文字列と使う文字列が別物になるため。
assert_field "toVersion: 3-part"            "$SEMVER_JSON" '.[0].toVersion' '2.0.0'
assert_field "toVersion: 2-part"            "$SEMVER_JSON" '.[3].toVersion' '1.1'
assert_field "toVersion: v prefix を剥がす" "$SEMVER_JSON" '.[4].toVersion' '4.2.0'
assert_field "toVersion: 末尾 in /path は入らない" "$SEMVER_JSON" '.[8].toVersion' '1.0.1'
assert_field "toVersion: semver unknown なら空" "$SEMVER_JSON" '.[7].toVersion' ''

# ---- package 名の whitelist (issue #330) ----
# `pnpm up <spec>` の引数は「名前」ではなく依存 spec 全体として解釈されるので、
# title 編集だけで別物を入れられる (実測: alias 形は既存依存を別 package に置換、
# glob は全依存を書き換え、tarball URL は当該ホストへ resolve しにいく)。
# npm 名 / GitHub Actions の owner/repo に一致しないものは個別維持に倒す。
BADPKG_JSON='[
  {"number":1,"title":"Bump --registry=http://evil from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/x","url":"u","body":"","labels":[]},
  {"number":2,"title":"Bump -g from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/x","url":"u","body":"","labels":[]},
  {"number":3,"title":"Bump lodash@npm:evil-pkg from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/x","url":"u","body":"","labels":[]},
  {"number":4,"title":"Bump * from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/x","url":"u","body":"","labels":[]},
  {"number":5,"title":"Bump !lodash from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/x","url":"u","body":"","labels":[]},
  {"number":6,"title":"Bump foo@https://evil.example/x.tgz from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/x","url":"u","body":"","labels":[]},
  {"number":7,"title":"Bump foo from 1.0.0 to 1.0.1\nBump --registry=http://evil from 2.0.0 to 3.0.0","headRefName":"dependabot/npm_and_yarn/x","url":"u","body":"","labels":[]}
]'
assert_field "bad package: option 形は unknown"          "$BADPKG_JSON" '.[0].semver' 'unknown'
assert_field "bad package: option 形は package を空に"   "$BADPKG_JSON" '.[0].package' ''
assert_field "bad package: option 形は toVersion も空に" "$BADPKG_JSON" '.[0].toVersion' ''
assert_field "bad package: 単一ハイフン形"               "$BADPKG_JSON" '.[1].semver' 'unknown'
assert_field "bad package: npm alias 形"                 "$BADPKG_JSON" '.[2].semver' 'unknown'
assert_field "bad package: glob"                         "$BADPKG_JSON" '.[3].semver' 'unknown'
assert_field "bad package: negation"                     "$BADPKG_JSON" '.[4].semver' 'unknown'
assert_field "bad package: tarball URL"                  "$BADPKG_JSON" '.[5].semver' 'unknown'
assert_field "bad package: 改行入り title"               "$BADPKG_JSON" '.[6].semver' 'unknown'
assert_field "bad package: 改行入り title は package も空" "$BADPKG_JSON" '.[6].package' ''

# whitelist が正規の名前を落としていないこと (fail-closed が広すぎると
# 統合が丸ごと機能しなくなるので、受理側も同じ強さで pin する)
GOODPKG_JSON='[
  {"number":1,"title":"Bump actions/checkout from 4.1.0 to 4.1.1","headRefName":"dependabot/github_actions/x","url":"u","body":"","labels":[]},
  {"number":2,"title":"Bump @secretlint/secretlint-formatter-sarif from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/x","url":"u","body":"","labels":[]},
  {"number":3,"title":"Bump lodash.merge from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/x","url":"u","body":"","labels":[]}
]'
assert_field "good package: owner/repo"  "$GOODPKG_JSON" '.[0].package' 'actions/checkout'
assert_field "good package: scoped npm"  "$GOODPKG_JSON" '.[1].package' '@secretlint/secretlint-formatter-sarif'
assert_field "good package: dot 入り"    "$GOODPKG_JSON" '.[2].package' 'lodash.merge'

# ---- commit-message prefix 付き title (issue #266) ----
# dependabot.yml の commit-message.prefix / include: scope で title 冒頭に
# 'Chore(deps): ' 等が付くと、以前は全件 semver=unknown / package="" に落ちた
# (別 repo で open PR 10 件全滅を実測)。実際に起きた事故の pin。
PREFIX_JSON='[
  {"number":1,"title":"Chore(deps): Bump actions/checkout from 4.1.1 to 4.2.0","headRefName":"dependabot/github_actions/actions/checkout-4.2.0","url":"u","body":"","labels":[]},
  {"number":2,"title":"chore: Bump foo from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":"","labels":[]},
  {"number":3,"title":"build(deps-dev): Bump @secretlint/secretlint-formatter-sarif from 8.0.0 to 9.0.0","headRefName":"dependabot/npm_and_yarn/x","url":"u","body":"","labels":[]},
  {"number":4,"title":"chore(deps): Bump foo from v1.2.3 to v1.2.4","headRefName":"dependabot/github_actions/foo","url":"u","body":"","labels":[]},
  {"number":5,"title":"Chore(deps): Bumps the gh-actions group with 2 updates: bumps foo from 1.0.0 to 1.0.1 and bar from 2.0.0 to 3.0.0","headRefName":"dependabot/github_actions/gh-actions","url":"u","body":"","labels":[]},
  {"number":6,"title":"chore(deps): Bump foo from 1.0.0 to 2.0.0-beta.1","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":"","labels":[]}
]'
assert_field "prefix: Chore(deps) minor"            "$PREFIX_JSON" '.[0].semver'  'minor'
assert_field "prefix: Chore(deps) package"          "$PREFIX_JSON" '.[0].package' 'actions/checkout'
assert_field "prefix: bare 'chore:' patch"          "$PREFIX_JSON" '.[1].semver'  'patch'
assert_field "prefix: build(deps-dev) major"        "$PREFIX_JSON" '.[2].semver'  'major'
assert_field "prefix: build(deps-dev) scoped npm package" "$PREFIX_JSON" '.[2].package' '@secretlint/secretlint-formatter-sarif'
assert_field "prefix: with v prefix versions"       "$PREFIX_JSON" '.[3].semver'  'patch'
assert_field "prefix + grouped → unknown"           "$PREFIX_JSON" '.[4].semver'  'unknown'
assert_field "prefix + pre-release to → unknown"    "$PREFIX_JSON" '.[5].semver'  'unknown'

# 受理パターンの広さ検査 (claude/rules/acceptance-patterns.md「fail-closed に
# したら、次は『受理パターンの広さ』を検査する」)。緩めた prefix パターンに
# **マッチしてしまう / してはいけない** 入力を構成して pin する。
PREFIX_NEG_JSON='[
  {"number":1,"title":"a(x): b: Bump foo from 1.0.0 to 2.0.0","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":"","labels":[]},
  {"number":2,"title":"Update readme: Bump foo from 1.0.0 to 2.0.0","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":"","labels":[]},
  {"number":3,"title":"chore:Bump foo from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":"","labels":[]},
  {"number":4,"title":": Bump foo from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":"","labels":[]},
  {"number":5,"title":"Note: Bump evil from 1.0.0 to 9.9.9","headRefName":"dependabot/npm_and_yarn/evil","url":"u","body":"","labels":[]}
]'
assert_field "prefix-neg: 多段 prefix は 1 回しか剥がれず unknown"  "$PREFIX_NEG_JSON" '.[0].semver'  'unknown'
assert_field "prefix-neg: 多段 prefix は package も空 (semver と整合)" "$PREFIX_NEG_JSON" '.[0].package' ''
assert_field "prefix-neg: token 内空白は prefix と認めず unknown"   "$PREFIX_NEG_JSON" '.[1].semver'  'unknown'
assert_field "prefix-neg: colon 後の空白必須 (chore:Bump) unknown"  "$PREFIX_NEG_JSON" '.[2].semver'  'unknown'
assert_field "prefix-neg: 空 prefix (': Bump') unknown"             "$PREFIX_NEG_JSON" '.[3].semver'  'unknown'
# 弁別不能な受理例。title だけでは Dependabot 生成物と区別できないため受理される。
# 実質のガードは呼び出し側の `gh pr list --author app/dependabot` フィルタ。
# 隠さず pin しておく (受理されなくなったらここが落ちて意図の変更に気付ける)。
assert_field "prefix-neg: 人間が書いた 'Note:' も受理される (author フィルタが実質のガード)" \
  "$PREFIX_NEG_JSON" '.[4].semver' 'major'

# ---- grouped PR 判定 (F3) ----
GROUP_JSON='[
  {"number":1,"title":"Bumps the all group with 2 updates: bumps foo from 1.0.0 to 1.0.1 and bar from 2.0.0 to 3.0.0","headRefName":"dependabot/github_actions/all","url":"u","body":"","labels":[]},
  {"number":2,"title":"Bump the deps group and bumps foo from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/deps","url":"u","body":"","labels":[]},
  {"number":3,"title":"Bumps the prod group and updates foo","headRefName":"dependabot/npm_and_yarn/prod","url":"u","body":"","labels":[]},
  {"number":4,"title":"Bump foo from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":"","labels":[]}
]'
assert_field "grouped: 'group with' unknown" "$GROUP_JSON" '.[0].semver' 'unknown'
assert_field "grouped: 'and bumps' unknown"  "$GROUP_JSON" '.[1].semver' 'unknown'
assert_field "grouped: 'and updates' unknown" "$GROUP_JSON" '.[2].semver' 'unknown'
assert_field "grouped: normal is not grouped" "$GROUP_JSON" '.[3].semver' 'patch'

# ---- security (F5) ----
SEC_JSON='[
  {"number":1,"title":"Bump lodash from 4.17.20 to 4.17.21","headRefName":"dependabot/npm_and_yarn/lodash","url":"u","body":"Fixes GHSA-abcd-1234-efgh in prod","labels":[]},
  {"number":2,"title":"Bump lodash from 4.17.20 to 4.17.21","headRefName":"dependabot/npm_and_yarn/lodash","url":"u","body":"See GitHub Security Advisory Database for details","labels":[]},
  {"number":3,"title":"Bump lodash from 4.17.20 to 4.17.21","headRefName":"dependabot/npm_and_yarn/lodash","url":"u","body":"","labels":[{"name":"security"}]},
  {"number":4,"title":"Bump lodash from 4.17.20 to 4.17.21","headRefName":"dependabot/npm_and_yarn/lodash","url":"u","body":"","labels":[{"name":"vulnerability"}]},
  {"number":5,"title":"Bump lodash from 4.17.20 to 4.17.21","headRefName":"dependabot/npm_and_yarn/lodash","url":"u","body":"","labels":[{"name":"Security"}]},
  {"number":6,"title":"Bump lodash from 4.17.20 to 4.17.21","headRefName":"dependabot/npm_and_yarn/lodash","url":"u","body":"","labels":[{"name":"security-review"}]},
  {"number":7,"title":"Bump lodash from 4.17.20 to 4.17.21","headRefName":"dependabot/npm_and_yarn/lodash","url":"u","body":"clean release notes","labels":[]},
  {"number":8,"title":"Bump lodash from 4.17.20 to 4.17.21","headRefName":"dependabot/npm_and_yarn/lodash","url":"u","body":"GHSA-abc-123 (partial, not real ID)","labels":[]}
]'
assert_field "security: real GHSA ID"                    "$SEC_JSON" '.[0].security' 'true'
assert_field "security: 'Security Advisory' false-positive fixed" "$SEC_JSON" '.[1].security' 'false'
assert_field "security: 'security' label"                "$SEC_JSON" '.[2].security' 'true'
assert_field "security: 'vulnerability' label"           "$SEC_JSON" '.[3].security' 'true'
assert_field "security: 'Security' capitalized label"    "$SEC_JSON" '.[4].security' 'true'
assert_field "security: 'security-review' partial label not matched" "$SEC_JSON" '.[5].security' 'false'
assert_field "security: no GHSA no security label"       "$SEC_JSON" '.[6].security' 'false'
assert_field "security: partial GHSA not matched"        "$SEC_JSON" '.[7].security' 'false'

# ---- stream / edge cases (F6, F7) ----
assert_field "empty array"    '[]' 'length' '0'
assert_exit  "empty stdin (invalid, caller must pass JSON array)" '' 'nonzero'

# JSON 出力が常に valid (F6)
MULTI_JSON='[
  {"number":1,"title":"Bump a from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/a","url":"u","body":"multi\nline\nbody","labels":[]},
  {"number":2,"title":"Bump b from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/b","url":"u","body":"tab\there","labels":[]}
]'
assert_field "stream: valid JSON on multi-line body" "$MULTI_JSON" 'length' '2'
assert_field "stream: multi-line body preserved"     "$MULTI_JSON" '.[0].title' 'Bump a from 1.0.0 to 1.0.1'

# body/labels 欠落
MISSING_JSON='[
  {"number":1,"title":"Bump a from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/a","url":"u","labels":[]}
]'
assert_field "stream: missing body → security false" "$MISSING_JSON" '.[0].security' 'false'

# ---- package (title 抽出) ----
PKG_JSON='[
  {"number":1,"title":"Bump actions/checkout from 4.1.1 to 4.2.0","headRefName":"dependabot/github_actions/x","url":"u","body":"","labels":[]},
  {"number":2,"title":"Bumps @secretlint/secretlint-formatter-sarif from 8.0.0 to 8.1.0","headRefName":"dependabot/npm_and_yarn/x","url":"u","body":"","labels":[]}
]'
assert_field "package: slash-name"      "$PKG_JSON" '.[0].package' 'actions/checkout'
assert_field "package: scoped npm"      "$PKG_JSON" '.[1].package' '@secretlint/secretlint-formatter-sarif'

# ---- label にカンマを含むケース (F5 追加) ----
COMMA_LABEL_JSON='[
  {"number":1,"title":"Bump lodash from 4.17.20 to 4.17.21","headRefName":"dependabot/npm_and_yarn/lodash","url":"u","body":"","labels":[{"name":"triage,security"}]}
]'
assert_field "security: comma in label name → false" "$COMMA_LABEL_JSON" '.[0].security' 'false'

# GHSA-ID 境界 (過長 / 埋め込み)
GHSA_BOUNDARY_JSON='[
  {"number":1,"title":"Bump foo from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":"Fixes GHSA-abcd-1234-efghi issue","labels":[]},
  {"number":2,"title":"Bump foo from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":"xGHSA-abcd-1234-efgh","labels":[]},
  {"number":3,"title":"Bump foo from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":"See advisory (GHSA-abcd-1234-efgh) for details","labels":[]}
]'
assert_field "security: GHSA over-long (5-char last group) → false" "$GHSA_BOUNDARY_JSON" '.[0].security' 'false'
assert_field "security: GHSA prefixed with alnum → false"           "$GHSA_BOUNDARY_JSON" '.[1].security' 'false'
assert_field "security: GHSA with paren/space boundary → true"      "$GHSA_BOUNDARY_JSON" '.[2].security' 'true'

# 壊れた JSON / 非配列 root (F qa-fixture 追加)
assert_exit "malformed JSON (missing brackets)" '{"a":1' 'nonzero'
assert_exit "non-array root (object)"           '{"foo":"bar"}' 'nonzero'

# labels 欠落 / null (F qa-fixture 追加、.labels[]? は missing / null を吸収)
LABELS_MISSING_JSON='[
  {"number":1,"title":"Bump foo from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":""},
  {"number":2,"title":"Bump foo from 1.0.0 to 1.0.1","headRefName":"dependabot/npm_and_yarn/foo","url":"u","body":"","labels":null}
]'
assert_field "labels missing → security false"   "$LABELS_MISSING_JSON" '.[0].security' 'false'
assert_field "labels null → security false"      "$LABELS_MISSING_JSON" '.[1].security' 'false'
assert_field "labels missing → still 2 elements" "$LABELS_MISSING_JSON" 'length'         '2'

# ---- jq 不在 (F7) ----
# PATH から jq を外して起動、非 0 終了になることを確認 (mktemp で空 PATH dir)
JQFREE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/jqfree.XXXXXX")
trap 'rm -rf "$JQFREE_DIR"' EXIT HUP INT TERM
# 最低限の bash / sed / cut / grep / cat を link
for cmd in bash sed cut grep cat printf; do
  cmd_path=$(command -v "$cmd") || continue
  ln -sf "$cmd_path" "$JQFREE_DIR/$cmd"
done
set +e
PATH="$JQFREE_DIR" bash "$CLASSIFIER" </dev/null >/dev/null 2>&1
jqfree_exit=$?
set -e
rm -rf "$JQFREE_DIR"
trap - EXIT HUP INT TERM
if [ "$jqfree_exit" != "0" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL: jq unavailable should exit non-zero (got $jqfree_exit)" >&2
fi

echo "dependabot-bulk classifier tests: $pass passed, $fail failed"
[ "$fail" = "0" ]
