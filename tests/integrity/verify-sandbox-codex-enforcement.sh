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
# 検査項目 (すべてファイル・ディレクトリの実在で判定する — mkdir / touch は
# 拒否されても環境によって exit 0 を返しうる):
#   1. repo 直下の保護対象ディレクトリを作れない
#   2. repo 配下ネストでも作れない
#   3. rename (mv) でも作れない (中身に触れずに丸ごと配置する経路)
#   4. 似た名前 (末尾に文字が付く形) は作れる = 過剰 deny でない
#   5. glob の `**` が 0 段にマッチするケースでも作れない
#      (`~/<1 セグメント>/<保護対象>/`。allowWrite に載っている `~/<保護対象>` を
#       1 セグメント目に使うと、home 直下に書き込めない環境でもこの合成を踏める)
#   6. `~/<保護対象>/` 配下への正当な書き込みは通る = codex CLI を壊していない
#      (glob 解釈が変わって sessions/ / auth.json が書けなくなる退行を拾う)
#
# **sandbox の外では skip する**。sandbox が無い環境 (素のターミナル / CI) では
# どれも成功するのが正しく、そこで fail させると「防御が壊れた」と誤読させる。
# 判定材料は codex / Claude Code が sandbox 内で立てる SANDBOX_RUNTIME=1。
# skip したことは必ず出力する — 「実行されなかった」を「pass した」と読ませない。
#
# fixture は実行ごとに一意な scratch ディレクトリ配下に作り、trap で後始末する。
# 固定名を repo 直下に作ると、既存の同名ディレクトリを巻き添えで消す・並列実行が
# 互いの fixture を触る、の 2 つが起きるため。**唯一 repo 直下に置くのは検査 1 の
# 保護対象そのもの**で、これは位置に意味があるので scratch に移せない — 代わりに
# 「実行前から在ったら消さずに FAIL させる」ガードを置く。
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

SCRATCH=""
HOME_PROBE_FILE=""
cleanup() {
  # 自分が作ったものだけを消す。rmdir は空でなければ失敗するので、
  # 想定外の中身が入っていたら残す (消して証拠を失わない)。
  [ -n "$HOME_PROBE_FILE" ] && rm -f "$HOME_PROBE_FILE" 2>/dev/null
  if [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ]; then
    rmdir "$SCRATCH/$protected" "$SCRATCH/${protected}-other" \
          "$SCRATCH/staged" "$SCRATCH/nest/$protected" "$SCRATCH/nest" 2>/dev/null
    rmdir "$SCRATCH" 2>/dev/null
  fi
  rmdir "$HOME/$protected/$protected" 2>/dev/null
}
trap cleanup EXIT HUP INT TERM

SCRATCH=$(mktemp -d "$REPO_ROOT/sbxprobe.XXXXXX") || {
  echo "FAIL: scratch ディレクトリを作成できなかった (検査不能)"
  exit 1
}

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

# --- 1. repo 直下 (位置に意味があるので scratch に移せない) ---
# 実行前から在る場合は消さずに FAIL。deny が効いていれば存在しえないので、
# 在ること自体が報告に値する状態であり、かつ他人の fixture を巻き添えにしない。
if [ -e "$REPO_ROOT/$protected" ]; then
  echo "FAIL: repo 直下に保護対象が実行前から存在する ($REPO_ROOT/$protected)。中身を確認すること (このテストは削除しない)"
  fail=$((fail + 1))
else
  check_dir_creation "repo 直下の保護対象" "$REPO_ROOT/$protected" deny
fi

# --- 2. repo 配下ネスト ---
check_dir_creation "repo 配下ネストの保護対象" "$SCRATCH/nest/$protected" deny
rmdir "$SCRATCH/nest" 2>/dev/null

# --- 3. rename 経路 ---
# deny が「配下への書き込み」だけを覆っていると、中身に一度も触れずに
# 丸ごと配置できてしまうため独立に測る。
if mkdir -p "$SCRATCH/staged" 2>/dev/null && [ -d "$SCRATCH/staged" ]; then
  mv "$SCRATCH/staged" "$SCRATCH/$protected" 2>/dev/null
  if [ -d "$SCRATCH/$protected" ]; then
    echo "FAIL: rename で保護対象を作成できてしまった"
    fail=$((fail + 1))
  else
    pass=$((pass + 1))
  fi
else
  echo "FAIL: rename 検査の staging ディレクトリを作成できなかった (検査不能)"
  fail=$((fail + 1))
fi

# --- 4. 過剰 deny の対照 ---
# deny されるべきなのは保護対象そのものだけで、名前が前方一致する別ディレクトリを
# 巻き込んでいないことを見る。
check_dir_creation "似た名前 (過剰 deny の対照)" "$SCRATCH/${protected}-other" allow

# --- 5. glob の `**` が 0 段にマッチするケース ---
# `~/<1 セグメント>/<保護対象>` はパターンの `*` が 1 段・`**` が 0 段に対応する。
# home 直下は allowWrite 外で fixture を置けないが、allowWrite に載っている
# `~/<保護対象>` を 1 セグメント目に流用すると同じ合成を踏める。
if [ -d "$HOME/$protected" ]; then
  check_dir_creation "home 直下 1 階層 (** が 0 段)" "$HOME/$protected/$protected" deny
else
  echo "SKIP: home 直下 1 階層の検査 ($HOME/$protected が無いため合成を踏めない)"
fi

# --- 6. codex CLI の正当な書き込みが生きていること ---
# 過剰 deny 側の退行 (sessions/ / auth.json が書けなくなる) を拾う。
if [ -d "$HOME/$protected" ]; then
  HOME_PROBE_FILE="$HOME/$protected/sbxprobe-enforcement-$$"
  touch "$HOME_PROBE_FILE" 2>/dev/null
  if [ -e "$HOME_PROBE_FILE" ]; then
    pass=$((pass + 1))
    rm -f "$HOME_PROBE_FILE" 2>/dev/null
    HOME_PROBE_FILE=""
  else
    echo "FAIL: home 配下の設定ディレクトリへ書けない — codex CLI の正当な書き込みを壊している"
    fail=$((fail + 1))
    HOME_PROBE_FILE=""
  fi
else
  echo "SKIP: home 配下の allow 検査 ($HOME/$protected が無い)"
fi

echo "sandbox codex enforcement: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
