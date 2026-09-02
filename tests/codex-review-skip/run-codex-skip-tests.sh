#!/usr/bin/env bash
set -euo pipefail

# codex-review run-review.sh の skip 判定 (exit 3/4) の回帰テスト。
#
# 検証観点:
#   - sandbox シグネチャ → exit 3
#   - usage limit / rate limit / too many requests (各単独) → exit 4
#   - 裸の数値 429 のみ / "rate limiter" 部分一致 / 汎用エラー → exit 1
#     (SKIP 誤判定で ERROR が隠蔽されない)
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

# codex stub: 呼ばれた事実を CODEX_CALLED_MARKER に残してから、CODEX_STDERR の
# 内容を stderr に出して失敗する。マーカーは preflight ケース (codex を起動せず
# SKIP する) の「起動していないこと」を assert するために要る。
mkdir -p "$WORKDIR/bin"
cat >"$WORKDIR/bin/codex" <<'EOF'
#!/bin/sh
[ -n "${CODEX_CALLED_MARKER:-}" ] && : >"$CODEX_CALLED_MARKER"
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
# proxy 変数を空にして走らせる: run-review.sh の network preflight (issue #335)
# は資格情報つき proxy を見つけると codex を起動せず exit 3 を返すため、ambient
# の設定を継承すると stderr シグネチャ系の全ケースが 3 に化ける (Claude Code の
# Bash sandbox 内で make test を回すと実際にそうなる)。preflight 自体の検査は
# 下の run_preflight_case が受け持つ。
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

# --- network preflight (issue #335) ---
#
# $1=名前, $2=期待 exit, $3=codex が起動されるべきか (yes|no), $4=proxy URL
#
# exit code だけでなく「codex を起動していないこと」も見る: preflight を
# 「codex を起動してから判定する」形に書き換えても exit 3 は返せてしまうが、
# それでは 600s ハングを避けるという目的を果たさない。
run_preflight_case() {
  local name="$1" want="$2" want_called="$3" proxy="$4" rc=0
  local marker="$WORKDIR/codex-called"
  rm -f "$marker"
  (cd "$FAKE_REPO" \
    && HTTPS_PROXY="$proxy" https_proxy="$proxy" \
       PATH="$WORKDIR/bin:$PATH" CODEX_STDERR="some other fatal error" \
       CODEX_CALLED_MARKER="$marker" \
       bash "$TARGET" security >/dev/null 2>&1) || rc=$?
  local called=no
  [ -f "$marker" ] && called=yes
  if [ "$rc" = "$want" ] && [ "$called" = "$want_called" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $name: expected=(exit $want, called $want_called) got=(exit $rc, called $called)"
    fail=$((fail + 1))
  fi
}

# 資格情報つき proxy → codex を起動せず 3。host は実測した localhost だけでなく
# 一般の proxy でも SKIP に倒す (誤検出側 = fail-safe。判定の広さの根拠は
# run-review.sh の preflight コメント)
#
# userinfo を変数経由で組み立てるのは、`http://<user>:<pass>@host` の形を
# リテラルで書くと secretlint の BasicAuth ルールが実在の資格情報として
# 検出し `make lint` が落ちるため (2026-09-02 実測)。
FAKE_USERINFO='user:pass'
run_preflight_case proxy-authed-localhost 3 no "http://$FAKE_USERINFO@localhost:54619"
run_preflight_case proxy-authed-remote    3 no "http://$FAKE_USERINFO@proxy.example.com:8080"

# 資格情報の無い proxy / proxy 無し → preflight を通り抜けて codex が起動し、
# stub の汎用エラーで 1 になる (preflight が広すぎないことの負例)
run_preflight_case proxy-anonymous 1 yes "http://localhost:54619"
run_preflight_case proxy-unset     1 yes ""

echo "codex-review-skip tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
