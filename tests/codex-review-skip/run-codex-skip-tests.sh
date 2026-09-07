#!/usr/bin/env bash
set -euo pipefail

# codex-review run-review.sh の skip 判定 (exit 3/4) の回帰テスト。
#
# 検証観点:
#   - sandbox シグネチャ → exit 3
#   - usage limit / rate limit / too many requests (各単独) → exit 4
#   - 裸の数値 429 のみ / "rate limiter" 部分一致 / 汎用エラー → exit 1
#     (SKIP 誤判定で ERROR が隠蔽されない)
#   - 終了しない codex を watchdog が打ち切る → exit 3 (issue #335)
#
# isolation: codex を PATH 先頭の stub に差し替え、CODEX_STDERR の内容を
# stderr に出して exit 1 する。git 前提条件 (base 超のコミット) は fake repo
# で満たす。run-review.sh は自身の物理パスから DOTFILES_ROOT を解決するため
# prompt ファイルは実 repo のものが使われる。

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
TARGET="$REPO_ROOT/claude/skills/codex-review/scripts/run-review.sh"

if [ ! -f "$TARGET" ]; then
  echo "ERROR: target not found: $TARGET" >&2
  exit 1
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-skip-tests.XXXXXX")"
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT

# codex stub: 呼ばれた事実を CODEX_CALLED_MARKER に残し、CODEX_SLEEP が
# 指定されていれば孫プロセスを 1 つ産んでからその秒数ぶん止まる (watchdog の
# ハング再現)。そうでなければ CODEX_STDERR の内容を stderr に出して失敗する。
# 孫の PID をファイルに書くのは、`pgrep -f sleep` のようなパターン一致だと
# host 上の無関係なプロセスを数えてしまうため。
mkdir -p "$WORKDIR/bin"
cat >"$WORKDIR/bin/codex" <<'EOF'
#!/bin/sh
[ -n "${CODEX_CALLED_MARKER:-}" ] && : >"$CODEX_CALLED_MARKER"
if [ -n "${CODEX_SLEEP:-}" ]; then
  sleep "$CODEX_SLEEP" &
  [ -n "${CODEX_GRANDCHILD_FILE:-}" ] && printf '%s\n' "$!" >"$CODEX_GRANDCHILD_FILE"
  sleep "$CODEX_SLEEP"
fi
printf '%s\n' "${CODEX_STDERR:-stub error}" >&2
exit 1
EOF
chmod +x "$WORKDIR/bin/codex"

# fake repo: main + feature (1 commit 先) で run-review.sh の前提を満たす
FAKE_REPO="$WORKDIR/repo"
mkdir -p "$FAKE_REPO"
git -C "$FAKE_REPO" init -q -b main
git -C "$FAKE_REPO" config user.email "test@example.com"
git -C "$FAKE_REPO" config user.name "test"
printf 'a\n' >"$FAKE_REPO/f.txt"
git -C "$FAKE_REPO" add -A
git -C "$FAKE_REPO" commit -qm base
git -C "$FAKE_REPO" checkout -qb feature
printf 'b\n' >>"$FAKE_REPO/f.txt"
git -C "$FAKE_REPO" add -A
git -C "$FAKE_REPO" commit -qm change

pass=0
fail=0

# $1=名前, $2=期待 exit, $3=stub の stderr 文言
#
# proxy 変数を空にして走らせる: stub は proxy を見ないが、ambient の設定を
# 引き回さないことでケースの独立性を保つ。
run_case() {
  local name="$1" want="$2" stderr_text="$3" rc=0
  (cd "$FAKE_REPO" \
    && HTTPS_PROXY='' https_proxy='' \
       PATH="$WORKDIR/bin:$PATH" CODEX_STDERR="$stderr_text" \
       bash "$TARGET" security >/dev/null 2>&1) || rc=$?
  if [ "$rc" = "$want" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $name: expected=$want got=$rc"
    fail=$((fail + 1))
  fi
}

# sandbox シグネチャ → 3
run_case sandbox-sig 3 "Error: failed to initialize in-process app-server client: Operation not permitted (os error 1)"

# rate limit 系 (各シグネチャ単独) → 4
run_case usage-limit     4 "You've hit your usage limit. Try again later."
run_case rate-limit      4 "Rate limit reached for requests"
run_case rate-limited    4 "You are being rate limited"
run_case too-many-reqs   4 "stream error: 429 Too Many Requests"

# SKIP 誤判定の負例 → 1 (ERROR のまま)
run_case bare-429        1 "connection to port 4290 failed"
run_case rate-limiter    1 "rate limiter initialization failed"
run_case generic-error   1 "some other fatal error"

# --- watchdog (issue #335) ---
#
# 終了しない codex を CODEX_REVIEW_TIMEOUT で打ち切って 3 を返すこと。
# 2026-09-02 に codex 0.152.1 が 60s バックオフに入って終了しなくなり、
# 呼び側が 600s 待たされて出力ゼロで終わった事故を pin する。
#
# 経過時間も見る: watchdog を外して「codex の終了を待ってから 3 を返す」形に
# 退化しても exit code だけなら一致してしまうが、それでは待たされる問題が
# 戻る。stub は 30s 眠るので、timeout=2 なら 30s より十分手前で返るはず。
GRANDCHILD_FILE="$WORKDIR/grandchild-pid"
rm -f "$GRANDCHILD_FILE"
watchdog_start=$(date +%s)
watchdog_rc=0
(cd "$FAKE_REPO" \
  && HTTPS_PROXY='' https_proxy='' \
     PATH="$WORKDIR/bin:$PATH" CODEX_SLEEP=30 CODEX_REVIEW_TIMEOUT=2 \
     CODEX_GRANDCHILD_FILE="$GRANDCHILD_FILE" \
     bash "$TARGET" security >/dev/null 2>&1) || watchdog_rc=$?
watchdog_elapsed=$(( $(date +%s) - watchdog_start ))
if [ "$watchdog_rc" = 3 ] && [ "$watchdog_elapsed" -lt 15 ]; then
  pass=$((pass + 1))
else
  echo "FAIL watchdog-hang: expected=(exit 3, elapsed <15s) got=(exit $watchdog_rc, elapsed ${watchdog_elapsed}s)"
  fail=$((fail + 1))
fi

# 打ち切りの巻き添えに孫プロセスも入ること。codex の直接の子だけ落とす形だと
# 孫が孤児として残り、実物では API を叩き続ける。stub が記録した PID だけを
# 見る (パターン一致だと host 上の無関係な sleep を数えてしまう)。
grandchild_pid="$(cat "$GRANDCHILD_FILE" 2>/dev/null || true)"
if [ -n "$grandchild_pid" ] && ! kill -0 "$grandchild_pid" 2>/dev/null; then
  pass=$((pass + 1))
else
  echo "FAIL watchdog-orphan: expected=(grandchild reaped) got=(pid '$grandchild_pid' still alive or unrecorded)"
  fail=$((fail + 1))
  [ -n "$grandchild_pid" ] && kill -KILL "$grandchild_pid" 2>/dev/null
fi

# CODEX_REVIEW_TIMEOUT の不正値 → codex を起動する前に ERROR。素通りさせると
# `-ge` 比較が毎回エラーになり、watchdog が永久に回る (打ち切りたい相手と
# 同じ壊れ方)。**exit code だけを見ない** — stub 自身も 1 で終わるので、
# 検証を削除しても exit 1 は返ってしまう (vacuous pass)。codex を起動して
# いないことをマーカーで見る。
#
# $1=名前, $2=渡す timeout 値
run_bad_timeout_case() {
  local name="$1" value="$2" rc=0
  local marker="$WORKDIR/codex-called"
  rm -f "$marker"
  (cd "$FAKE_REPO" \
    && HTTPS_PROXY='' https_proxy='' \
       PATH="$WORKDIR/bin:$PATH" CODEX_STDERR="some other fatal error" \
       CODEX_CALLED_MARKER="$marker" CODEX_REVIEW_TIMEOUT="$value" \
       bash "$TARGET" security >/dev/null 2>&1) || rc=$?
  local called=no
  [ -f "$marker" ] && called=yes
  if [ "$rc" = 1 ] && [ "$called" = no ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $name: expected=(exit 1, codex not called) got=(exit $rc, called $called)"
    fail=$((fail + 1))
  fi
}

run_bad_timeout_case bad-timeout-nonnumeric abc
run_bad_timeout_case bad-timeout-zero       0

# 資格情報つき proxy でも codex を起動すること。ここを「起動せず SKIP」に
# 戻すと、上流が直っても skill が使えないままになる (2026-09-02 に置いた
# preflight で実際にそうなった。issue #335)。
#
# userinfo を変数経由で組み立てるのは、`http://<user>:<pass>@host` の形を
# リテラルで書くと secretlint の BasicAuth ルールが実在の資格情報として
# 検出し `make lint` が落ちるため (2026-09-02 実測)。
FAKE_USERINFO='user:pass'
proxy_marker="$WORKDIR/codex-called"
rm -f "$proxy_marker"
proxy_rc=0
(cd "$FAKE_REPO" \
  && HTTPS_PROXY="http://$FAKE_USERINFO@localhost:54619" \
     https_proxy="http://$FAKE_USERINFO@localhost:54619" \
     PATH="$WORKDIR/bin:$PATH" CODEX_STDERR="some other fatal error" \
     CODEX_CALLED_MARKER="$proxy_marker" \
     bash "$TARGET" security >/dev/null 2>&1) || proxy_rc=$?
proxy_called=no
[ -f "$proxy_marker" ] && proxy_called=yes
if [ "$proxy_rc" = 1 ] && [ "$proxy_called" = yes ]; then
  pass=$((pass + 1))
else
  echo "FAIL proxy-authed-still-runs: expected=(exit 1, codex called) got=(exit $proxy_rc, called $proxy_called)"
  fail=$((fail + 1))
fi

echo "codex-review-skip tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
