#!/usr/bin/env bash
set -euo pipefail

# codex-review run-review.sh の skip 判定 (exit 3/4/5) と生成ファイル除外の
# 回帰テスト。
#
# 検証観点:
#   - sandbox シグネチャ → exit 3
#   - usage limit / rate limit / too many requests (各単独) → exit 4
#   - 入力上限 (input_too_large) → exit 5
#   - linguist-generated なファイルを diff から外す
#   - 裸の数値 429 のみ / "rate limiter" 部分一致 / 汎用エラー → exit 1
#     (SKIP 誤判定で ERROR が隠蔽されない)
#   - 終了しない codex を watchdog が打ち切る → exit 3 (issue #335)
#   - codex に CA バンドルをファイルで渡す / user 指定の CA は上書きしない
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
[ -n "${CODEX_CA_RECORD:-}" ] && printf '%s' "${CODEX_CA_CERTIFICATE:-}" >"$CODEX_CA_RECORD"
[ -n "${CODEX_STDIN_RECORD:-}" ] && cat >"$CODEX_STDIN_RECORD"
if [ -n "${CODEX_SLEEP:-}" ]; then
  sleep "$CODEX_SLEEP" &
  [ -n "${CODEX_GRANDCHILD_FILE:-}" ] && printf '%s\n' "$!" >"$CODEX_GRANDCHILD_FILE"
  sleep "$CODEX_SLEEP"
fi
printf '%s\n' "${CODEX_STDERR:-stub error}" >&2
exit 1
EOF
chmod +x "$WORKDIR/bin/codex"

# clone の origin/HEAD は元 repo の HEAD (feature) を指すので、base を main に
# 戻しておく (run-review.sh は origin/HEAD から base を決める)。
configure_repo() {
  if git -C "$1" remote get-url origin >/dev/null 2>&1; then
    git -C "$1" remote set-head origin main
  fi
  git -C "$1" config user.email "test@example.com"
  git -C "$1" config user.name "test"
  git -C "$1" config gc.auto 0
  git -C "$1" config maintenance.auto false
}

# fake repo: main + feature (1 commit 先) で run-review.sh の前提を満たす。
# feature 側に linguist-generated なファイルは無い (除外が空の経路)
FAKE_REPO="$WORKDIR/repo"
mkdir -p "$FAKE_REPO/sub"
git -C "$FAKE_REPO" init -q -b main
configure_repo "$FAKE_REPO"
printf 'a\n' >"$FAKE_REPO/f.txt"
printf 'gen/*.csv linguist-generated=true\n' >"$FAKE_REPO/.gitattributes"
printf 'keep\n' >"$FAKE_REPO/sub/keep.txt"
git -C "$FAKE_REPO" add -A
git -C "$FAKE_REPO" commit -qm base
git -C "$FAKE_REPO" checkout -qb feature
printf 'b\n' >>"$FAKE_REPO/f.txt"
git -C "$FAKE_REPO" add -A
git -C "$FAKE_REPO" commit -qm change

# FAKE_REPO の <起点> から feature を切り、生成ファイルを 1 commit 足した
# clone を <dest> に作る (issue #410)
make_gen_repo() {
  local dest="$1" from="$2"
  git clone -q -b "$from" "$FAKE_REPO" "$dest"
  configure_repo "$dest"
  git -C "$dest" checkout -qB feature
  mkdir -p "$dest/gen"
  printf 'GENERATED_ROW_MARKER\n' >"$dest/gen/data.csv"
  git -C "$dest" add -A
  git -C "$dest" commit -qm generated
}

# GEN_REPO: 通常ファイルの変更 + 生成ファイル / GEN_ONLY_REPO: 生成ファイルだけ
GEN_REPO="$WORKDIR/gen-repo"
make_gen_repo "$GEN_REPO" feature
GEN_ONLY_REPO="$WORKDIR/gen-only-repo"
make_gen_repo "$GEN_ONLY_REPO" main

# BRANCH_ATTR_REPO: レビュー対象のブランチ自身が f.txt に属性を付ける
BRANCH_ATTR_REPO="$WORKDIR/branch-attr-repo"
git clone -q -b feature "$FAKE_REPO" "$BRANCH_ATTR_REPO"
configure_repo "$BRANCH_ATTR_REPO"
printf 'f.txt linguist-generated=true\n' >>"$BRANCH_ATTR_REPO/.gitattributes"
git -C "$BRANCH_ATTR_REPO" add -A
git -C "$BRANCH_ATTR_REPO" commit -qm hide

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

# 入力上限 → 5 (codex-cli 0.161.0 の実際の stderr。issue #410)
run_case input-too-large 5 'Error: turn/start: turn/start failed: Input exceeds the maximum length of 1048576 characters. (code -32602), data: {"input_error_code":"input_too_large","max_chars":1048576,"actual_chars":1100010}'

# SKIP 誤判定の負例 → 1 (ERROR のまま)
run_case bare-429        1 "connection to port 4290 failed"
run_case rate-limiter    1 "rate limiter initialization failed"
run_case generic-error   1 "some other fatal error"

# --- linguist-generated の除外 (issue #410) ---
#
# 生成ファイルの中身が prompt に入らず、名前は除外節に載り、通常ファイルの
# diff は残ること。サブディレクトリからも見る: --name-only は toplevel 基準の
# パスを返すので、cwd 基準で解釈すると除外が外れる。除外したことは呼び側
# (stderr) にも出ること。
#
# $1=名前, $2=run-review.sh を走らせるディレクトリ
run_exclude_case() {
  local name="$1" dir="$2" record="$WORKDIR/codex-stdin" err="$WORKDIR/run-stderr" problems=""
  rm -f "$record"
  (cd "$dir" \
    && HTTPS_PROXY='' https_proxy='' \
       PATH="$WORKDIR/bin:$PATH" CODEX_STDIN_RECORD="$record" \
       bash "$TARGET" security >/dev/null 2>"$err") || true
  if [ ! -f "$record" ]; then
    problems="codex not called"
  else
    grep -qF 'GENERATED_ROW_MARKER' "$record" && problems="$problems generated-content-in-prompt"
    grep -qF '## Excluded from the diff' "$record" || problems="$problems no-excluded-section"
    grep -qF 'gen/data.csv' "$record" || problems="$problems excluded-file-unnamed"
    grep -qxF '+b' "$record" || problems="$problems regular-diff-missing"
  fi
  grep -qF 'excluded from review' "$err" || problems="$problems not-reported-to-caller"
  if [ -z "$problems" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $name:$problems"
    fail=$((fail + 1))
  fi
}

run_exclude_case exclude-generated-root   "$GEN_REPO"
run_exclude_case exclude-generated-subdir "$GEN_REPO/sub"

# ブランチが付けた属性では除外しないこと (base の .gitattributes だけを見る)。
# working tree の属性で判定すると、レビュー対象自身が任意のファイルを隠せる。
branch_attr_record="$WORKDIR/codex-stdin-branch-attr"
rm -f "$branch_attr_record"
(cd "$BRANCH_ATTR_REPO" \
  && HTTPS_PROXY='' https_proxy='' \
     PATH="$WORKDIR/bin:$PATH" CODEX_STDIN_RECORD="$branch_attr_record" \
     bash "$TARGET" security >/dev/null 2>&1) || true
if [ -f "$branch_attr_record" ] && grep -qxF '+b' "$branch_attr_record" \
  && ! grep -qF '## Excluded from the diff' "$branch_attr_record"; then
  pass=$((pass + 1))
else
  echo "FAIL branch-added-attr-ignored: f.txt was hidden from the prompt (or codex not called)"
  fail=$((fail + 1))
fi

# 変更が生成ファイルだけなら codex を呼ばずに ERROR。空の diff を渡すと、
# 何も見ていないのに pass が返りうる。
# 文言も見るのは、他の起動前 ERROR (base 解決失敗等) でも exit 1・未起動に
# なり、fixture がこの分岐まで届かなくなっても green のままになるため。
gen_only_rc=0
gen_only_marker="$WORKDIR/codex-called-gen-only"
gen_only_err="$WORKDIR/gen-only-stderr"
rm -f "$gen_only_marker"
(cd "$GEN_ONLY_REPO" \
  && HTTPS_PROXY='' https_proxy='' \
     PATH="$WORKDIR/bin:$PATH" CODEX_CALLED_MARKER="$gen_only_marker" \
     bash "$TARGET" security >/dev/null 2>"$gen_only_err") || gen_only_rc=$?
if [ "$gen_only_rc" = 1 ] && [ ! -f "$gen_only_marker" ] \
  && grep -qF 'every changed file is linguist-generated' "$gen_only_err"; then
  pass=$((pass + 1))
else
  gen_only_called=no
  [ -f "$gen_only_marker" ] && gen_only_called=yes
  echo "FAIL exclude-all-generated: expected=(exit 1, called no, all-generated message) got=(exit $gen_only_rc, called $gen_only_called): $(cat "$gen_only_err")"
  fail=$((fail + 1))
fi

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
# 消えるまで少し待つ: 直後の単発 kill -0 は、reap 前の zombie に対しても
# 成功しうるので偽 FAIL になる。
gc_waited=0
while [ -n "$grandchild_pid" ] && kill -0 "$grandchild_pid" 2>/dev/null; do
  if [ "$gc_waited" -ge 5 ]; then
    break
  fi
  sleep 1
  gc_waited=$((gc_waited + 1))
done
if [ -n "$grandchild_pid" ] && ! kill -0 "$grandchild_pid" 2>/dev/null; then
  pass=$((pass + 1))
else
  echo "FAIL watchdog-orphan: expected=(grandchild reaped) got=(pid '$grandchild_pid' still alive or unrecorded)"
  fail=$((fail + 1))
  if [ -n "$grandchild_pid" ]; then
    kill -KILL "$grandchild_pid" 2>/dev/null || true
  fi
fi

# CODEX_REVIEW_TIMEOUT の不正値 → codex を起動する前に ERROR。素通りさせると
# `-ge` 比較が毎回エラーになり、watchdog が永久に回る (打ち切りたい相手と
# 同じ壊れ方)。**exit code だけを見ない** — stub 自身も 1 で終わるので、
# 検証を削除しても exit 1 は返ってしまう (vacuous pass)。codex を起動して
# いないことをマーカーで見る。
#
# $1=名前, $2=期待 exit, $3=codex が起動されるべきか (yes|no),
# $4=CODEX_REVIEW_TIMEOUT (空なら既定の 300), $5=proxy URL (空なら proxy 無し)
run_marker_case() {
  local name="$1" want="$2" want_called="$3" timeout="$4" proxy="$5" rc=0
  local marker="$WORKDIR/codex-called"
  rm -f "$marker"
  (cd "$FAKE_REPO" \
    && HTTPS_PROXY="$proxy" https_proxy="$proxy" \
       PATH="$WORKDIR/bin:$PATH" CODEX_STDERR="some other fatal error" \
       CODEX_CALLED_MARKER="$marker" \
       env ${timeout:+"CODEX_REVIEW_TIMEOUT=$timeout"} \
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

run_marker_case bad-timeout-nonnumeric 1 no abc ''
run_marker_case bad-timeout-zero       1 no 0   ''

# 資格情報つき proxy でも codex を起動すること。ここを「起動せず SKIP」に
# 戻すと、上流が直っても skill が使えないままになる (2026-09-02 に置いた
# preflight で実際にそうなった。issue #335)。
#
# userinfo を変数経由で組み立てるのは、`http://<user>:<pass>@host` の形を
# リテラルで書くと secretlint の BasicAuth ルールが実在の資格情報として
# 検出し `make lint` が落ちるため (2026-09-02 実測)。
FAKE_USERINFO='user:pass'
run_marker_case proxy-authed-still-runs 1 yes '' "http://$FAKE_USERINFO@localhost:54619"

# codex に CA バンドルをファイルで渡すこと。既定のシステム証明書ストアでの
# 検証は sandbox 内で通らず、codex-review が exit 1 になっていた (2026-09-25)。
# user が CA を自分で指定しているときは上書きしないこと。
#
# バンドルの置き場は CODEX_REVIEW_CA_BUNDLE で差し替え、host の
# Homebrew バンドルの有無に結果を左右させない。
#
# $1=名前, $2=環境に与える CODEX_CA_CERTIFICATE (空なら未設定),
# $3=SSL_CERT_FILE (空なら未設定), $4=CODEX_REVIEW_CA_BUNDLE,
# $5=codex が受け取るべき値
run_ca_case() {
  local name="$1" given="$2" ssl="$3" bundle="$4" want="$5"
  local record="$WORKDIR/codex-ca" got
  rm -f "$record"
  (cd "$FAKE_REPO" \
    && HTTPS_PROXY='' https_proxy='' \
       PATH="$WORKDIR/bin:$PATH" CODEX_CA_RECORD="$record" \
       env -u SSL_CERT_FILE -u CODEX_CA_CERTIFICATE \
         ${given:+"CODEX_CA_CERTIFICATE=$given"} \
         ${ssl:+"SSL_CERT_FILE=$ssl"} \
         CODEX_REVIEW_CA_BUNDLE="$bundle" \
         bash "$TARGET" security >/dev/null 2>&1) || true
  got="$(cat "$record" 2>/dev/null || printf '<not called>')"
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $name: expected CODEX_CA_CERTIFICATE='$want' got='$got'"
    fail=$((fail + 1))
  fi
}

FAKE_BUNDLE="$WORKDIR/ca.pem"
: >"$FAKE_BUNDLE"
run_ca_case ca-default        ''             ''             "$FAKE_BUNDLE"         "$FAKE_BUNDLE"
run_ca_case ca-bundle-missing ''             ''             "$WORKDIR/missing.pem" ''
run_ca_case ca-bundle-dir     ''             ''             "$WORKDIR"             ''
run_ca_case ca-user-override  /custom/ca.pem ''             "$FAKE_BUNDLE"         /custom/ca.pem
run_ca_case ca-ssl-cert-file  ''             /custom/ca.pem "$FAKE_BUNDLE"         ''

echo "codex-review-skip tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
