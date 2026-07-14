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
  {"number":4,"title":"Bump d from 1.0.0 to 1.0.1","headRefName":"random/branch","url":"u","body":"","labels":[]}
]'
assert_field "ecosystem: github_actions"  "$ECO_JSON" '.[0].ecosystem' 'github-actions'
assert_field "ecosystem: npm_and_yarn"    "$ECO_JSON" '.[1].ecosystem' 'npm'
assert_field "ecosystem: other dependabot"    "$ECO_JSON" '.[2].ecosystem' 'unknown'
assert_field "ecosystem: non-dependabot"      "$ECO_JSON" '.[3].ecosystem' 'unknown'

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
