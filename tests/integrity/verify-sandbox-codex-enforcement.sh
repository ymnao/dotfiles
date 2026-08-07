#!/usr/bin/env bash
#
# claude/settings.json の denyWrite エントリ `~/*/**/.codex/**` が
# **実際に書き込みを止めているか**を挙動で検査する (issue #289)。
#
# verify-settings-codex-domains.sh は「エントリが設定に在ること」しか見ない。
# それはプロキシであって enforcement の証明ではなく、Claude Code / Seatbelt の
# glob 解釈が変わっても緑のままになる。claude/rules/shell.md の
# 「環境の前提を assert するときは *守りたい挙動そのもの* を測る」に従い、
# 実際に mkdir / mv を試して拒否されることを確かめる。
#
# 検査項目 (すべてファイルの実在で判定する — mkdir / touch は拒否されても
# 環境によって exit 0 を返しうる):
#   1. repo 直下の保護対象ディレクトリを作れない
#   2. repo 配下ネストでも作れない
#   3. rename (mv) でも作れない (中身に触れずに丸ごと配置する経路)
#   4. 似た名前 (末尾に文字が付く形) は作れる = 過剰 deny でない
#
# **sandbox の外では skip する**。sandbox が無い環境 (素のターミナル / CI) では
# どれも成功するのが正しく、そこで fail させると「防御が壊れた」と誤読させる。
# 判定材料は codex / Claude Code が sandbox 内で立てる SANDBOX_RUNTIME=1。
# skip したことは必ず出力する — 「実行されなかった」を「pass した」と読ませない。
#
# 依存: bash 3.2+

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"

if [ "${SANDBOX_RUNTIME:-}" != "1" ]; then
  echo "sandbox codex enforcement: SKIP (sandbox 外で実行されたため。SANDBOX_RUNTIME=1 のときだけ測る)"
  exit 0
fi

# 保護対象ディレクトリ名は分割して組み立てる。このスクリプト自体は make 経由で
# 起動されるので hook には引っかからないが、grep やコピーで literal が
# 出回ると別経路で誤ブロックの種になるため揃えておく。
protected='.co'
protected="${protected}dex"

pass=0
fail=0

# $1=説明, $2=対象ディレクトリ, $3=expect (deny|allow)
check_dir_creation() {
  local desc="$1" dir="$2" expect="$3"
  mkdir -p "$dir" 2>/dev/null
  if [ -d "$dir" ]; then
    rmdir "$dir" 2>/dev/null
    if [ "$expect" = "allow" ]; then
      pass=$((pass + 1))
    else
      echo "FAIL: $desc — 作成できてしまった ($dir)"
      fail=$((fail + 1))
    fi
  else
    if [ "$expect" = "deny" ]; then
      pass=$((pass + 1))
    else
      echo "FAIL: $desc — 作成できるはずが拒否された ($dir)"
      fail=$((fail + 1))
    fi
  fi
}

check_dir_creation "repo 直下の保護対象" "$REPO_ROOT/$protected" deny
check_dir_creation "repo 配下ネストの保護対象" "$REPO_ROOT/sbxprobe-nest/$protected" deny
rmdir "$REPO_ROOT/sbxprobe-nest" 2>/dev/null
# 過剰 deny の対照。deny されるべきなのは保護対象そのものだけで、
# 名前が前方一致する別ディレクトリまで巻き込んでいないことを見る。
check_dir_creation "似た名前 (過剰 deny の対照)" "$REPO_ROOT/${protected}-sbxprobe" allow

# rename 経路: 別名で用意したディレクトリを保護対象名に改名できないこと。
# deny が「配下への書き込み」だけを覆っていると、中身に一度も触れずに
# 丸ごと配置できてしまうため独立に測る。
staged="$REPO_ROOT/sbxprobe-staged"
mkdir -p "$staged" 2>/dev/null
if [ -d "$staged" ]; then
  mv "$staged" "$REPO_ROOT/$protected" 2>/dev/null
  if [ -d "$REPO_ROOT/$protected" ]; then
    echo "FAIL: rename で保護対象を作成できてしまった"
    fail=$((fail + 1))
    rmdir "$REPO_ROOT/$protected" 2>/dev/null
  else
    pass=$((pass + 1))
  fi
  rmdir "$staged" 2>/dev/null
else
  echo "FAIL: rename 検査の staging ディレクトリを作成できなかった (検査不能)"
  fail=$((fail + 1))
fi

echo "sandbox codex enforcement: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
