#!/usr/bin/env bash
set -euo pipefail

# merge-gate.sh の判定を一時 git リポジトリで確かめる

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
GATE="$REPO_ROOT/claude/skills/pr/scripts/merge-gate.sh"
CODEX_GATE="$REPO_ROOT/codex/skills/pr/scripts/merge-gate.sh"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/merge-gate.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

cd "$WORKDIR"
git init -q -b main .
git config user.email "test@example.com"
git config user.name "test"
git config diff.renames true
git config gc.auto 0
git config maintenance.auto false

mkdir -p .claude scripts sub
printf 'REQUIRE_REVIEW_PATH=^scripts/link\\.sh$\n# comment\n\n' > .claude/merge-gate.conf
echo "link" > scripts/link.sh
echo "keep" > sub/keep.sh
echo "gone" > sub/gone.sh
git add .
git commit -qm "init"

pass=0
fail=0
branch_no=0

new_branch() {
  git checkout -q main
  branch_no=$((branch_no + 1))
  git checkout -q -b "case-$branch_no"
}

commit_all() {
  git add -A
  git commit -qm "change"
}

# assert_gate <name> <verdict> <reason の部分文字列 ("" で reasons が空)> <files を空白で連結した値>
assert_gate() {
  local name="$1" want_verdict="$2" want_reason="$3" want_files="$4" out verdict reasons got_files
  out=$(bash "${GATE_UNDER_TEST:-$GATE}" main)
  verdict=$(printf '%s' "$out" | jq -r '.verdict')
  reasons=$(printf '%s' "$out" | jq -r '.reasons | join(" ")')
  got_files=$(printf '%s' "$out" | jq -r '.files | join(" ")')
  if [ "$verdict" != "$want_verdict" ] || [ "$got_files" != "$want_files" ]; then
    echo "FAIL $name: $out"
    fail=$((fail + 1))
    return
  fi
  case "$want_reason:$reasons" in
    :) pass=$((pass + 1)) ;;
    ?*:*"$want_reason"*) pass=$((pass + 1)) ;;
    *)
      echo "FAIL $name: reason: $out"
      fail=$((fail + 1))
      ;;
  esac
}

# assert_gate_error <name> <stderr の部分文字列>
assert_gate_error() {
  local name="$1" want="$2" status=0 err
  err=$(bash "$GATE" main 2>&1 >/dev/null) || status=$?
  case "$status:$err" in
    1:*"$want"*) pass=$((pass + 1)) ;;
    *)
      echo "FAIL $name: status=$status stderr=$err"
      fail=$((fail + 1))
      ;;
  esac
}

new_branch
echo "x" >> sub/keep.sh
commit_all
assert_gate "該当なしは候補" "候補" "" ""

new_branch
echo 'brew "jq"' > Brewfile
commit_all
assert_gate "tier=high は要確認" "要確認" "tier-high: dependency" ""

new_branch
echo "x" >> scripts/link.sh
commit_all
assert_gate "conf の条件に一致すると要確認" "要確認" "conf-path: scripts/link.sh" "scripts/link.sh"

new_branch
git mv scripts/link.sh scripts/moved.sh
commit_all
assert_gate "conf の対象を別名へ動かしても要確認" "要確認" "conf-path: scripts/link.sh" "scripts/link.sh"

new_branch
git rm -q sub/gone.sh
commit_all
assert_gate "削除は要確認" "要確認" "deleted: sub/gone.sh" "sub/gone.sh"

new_branch
printf '# no conditions\n' > .claude/merge-gate.conf
echo "x" >> scripts/link.sh
commit_all
assert_gate "PR で conf の条件を消しても base の版で判定する" "要確認" "conf-path: scripts/link.sh" ".claude/merge-gate.conf scripts/link.sh"

new_branch
printf 'REQUIRE_REVIEW_PATH=^none$\n' >> .claude/merge-gate.conf
commit_all
assert_gate "conf の変更は要確認" "要確認" "conf-change: .claude/merge-gate.conf" ".claude/merge-gate.conf"

new_branch
echo "x" >> sub/keep.sh
commit_all
GATE_UNDER_TEST="$CODEX_GATE" assert_gate "codex 側の配置からも動く" "候補" "" ""

git checkout -q main
printf 'REQUIRE_REVIEW_PATH=^unclosed($\n' > .claude/merge-gate.conf
commit_all
new_branch
echo "x" >> sub/keep.sh
commit_all
assert_gate_error "不正な ERE は判定を止める" "invalid pattern"

git checkout -q main
printf 'REQUIRE_REVIEW_PATH=\n' > .claude/merge-gate.conf
commit_all
new_branch
echo "x" >> sub/keep.sh
commit_all
assert_gate_error "空のパターンは判定を止める" "unknown line"

git checkout -q main
printf 'REQUIRE_REVIEW_PATHS=^scripts/\n' > .claude/merge-gate.conf
commit_all
new_branch
echo "x" >> sub/keep.sh
commit_all
assert_gate_error "綴りの違うキーは判定を止める" "unknown line"

git checkout -q main
git rm -q .claude/merge-gate.conf
commit_all
new_branch
echo "x" >> scripts/link.sh
commit_all
assert_gate "conf が無い repo では tier と削除だけで判定する" "候補" "" ""

new_branch
git rm -q sub/gone.sh
commit_all
assert_gate "conf が無い repo でも削除は要確認" "要確認" "deleted: sub/gone.sh" "sub/gone.sh"

status=0
(cd "$WORKDIR" && bash "$GATE" no-such-branch >/dev/null 2>&1) || status=$?
if [ "$status" -eq 1 ]; then
  pass=$((pass + 1))
else
  echo "FAIL base が見つからなければ exit 1: status=$status"
  fail=$((fail + 1))
fi

echo "merge-gate: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
