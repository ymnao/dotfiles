#!/usr/bin/env bash
#
# agents/hooks/hooks-integrity-warn.sh の回帰テスト (issue #207)。
#
# 検証内容:
#   1. 検知ロジック — 監視対象パスの未コミット改変だけを警告し、対象外の
#      変更や clean な repo では何も出さない。常に exit 0 (warn-only)
#   2. 配線 — claude/hooks/ からの symlink・settings.json の SessionStart
#      エントリ・tests/run-gate.sh からの呼び出しが揃っている
#
# 一時 git repo を $TMPDIR に作って検知ロジックを回す。検査対象 repo は
# HOOKS_INTEGRITY_REPO で差し替える (hook 側が用意している上書き口)。

# -e を追加すると、期待値が非 0 のケース (grep -q の不一致、fail-open 経路の確認)
# でランナー自身が死ぬため使わない。失敗は check / check_cmd / check_empty で
# 明示的に集計する (tests/verify-ci/run-verify-ci-tests.sh と同じ方針)。
set -uo pipefail

# 期待文字列 (日本語) をバイト一致で比較するためロケールを固定する。
# ambient ロケール依存で grep の一致判定が揺れるのを防ぐ (issue #181 / #192)。
export LC_ALL=C

# 開発者環境の ~/.gitconfig (commit.gpgsign=true / core.hooksPath / core.excludesFile 等) が
# fixture の初期コミットを spurious fail させないよう global/system config を切り離す
# (tests/verify-ci/run-verify-ci-tests.sh と同じ規約)。
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
HOOK="$REPO_ROOT/agents/hooks/hooks-integrity-warn.sh"

pass=0
fail=0

check() {
  # $1=condition (0=OK), $2=description
  if [ "$1" = "0" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL: $2"
    fail=$((fail + 1))
  fi
}

# `[ ... ]` の直後に `check "$?"` と書くと SC2319 になるため、条件は
# コマンドとしてヘルパーに渡す (`[` は外部/組み込みコマンドなので "$@" で実行できる)。
check_cmd() {
  # $1=description, $2 以降=判定コマンド
  local desc="$1"
  shift
  if "$@"; then
    pass=$((pass + 1))
  else
    echo "FAIL: $desc"
    fail=$((fail + 1))
  fi
}

check_empty() {
  # $1=検査する出力, $2=description
  if [ -z "$1" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL: $2 (got: $1)"
    fail=$((fail + 1))
  fi
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/hooks-integrity-test.XXXXXX") || exit 1

# ケース 12 は実 dotfiles repo を dirty にして検知を確認する。中断で残留すると
# SessionStart 警告に出続けて signal を潰すため、PID 付きの名前にして
# (並列実行で他プロセスの probe を消さない) trap の cleanup 対象に入れる。
PROBE="$REPO_ROOT/agents/hooks/.hooks-integrity-probe.$$"

cleanup() {
  rm -rf "$WORK"
  rm -f "$PROBE"
}
trap cleanup EXIT INT TERM

FIXTURE="$WORK/repo"
mkdir -p "$FIXTURE/agents/hooks" "$FIXTURE/claude/hooks" "$FIXTURE/codex/hooks"
printf 'echo base\n' > "$FIXTURE/agents/hooks/sample.sh"
printf '{}\n' > "$FIXTURE/codex/hooks.json"
printf '{}\n' > "$FIXTURE/claude/settings.json"
printf 'readme\n' > "$FIXTURE/README.md"
# 本番と同じく claude/hooks/ は agents/hooks/ への相対 symlink にしておく
# (symlink が実体ファイルに置換される typechange も検知対象に入るため)。
ln -s ../../agents/hooks/sample.sh "$FIXTURE/claude/hooks/sample.sh"

git -C "$FIXTURE" init -q
git -C "$FIXTURE" add -A
git -C "$FIXTURE" \
  -c user.email=test@example.com \
  -c user.name=test \
  commit -qm "init"

run_hook() {
  HOOKS_INTEGRITY_REPO="$1" bash "$HOOK" 2>&1
}

# --- 1. clean な repo では何も出さない ---
out=$(run_hook "$FIXTURE"); rc=$?
check "$rc" "clean repo で exit 0 を返すこと (got $rc)"
check_empty "$out" "clean repo で出力が空であること"

# --- 2. 監視対象外の変更は無視する ---
printf 'changed\n' >> "$FIXTURE/README.md"
out=$(run_hook "$FIXTURE"); rc=$?
check "$rc" "対象外変更のみでも exit 0 (got $rc)"
check_empty "$out" "対象外変更 (README.md) を警告しないこと"

# --- 3. 正本 hook の改変を検知する ---
printf 'echo tampered\n' >> "$FIXTURE/agents/hooks/sample.sh"
out=$(run_hook "$FIXTURE"); rc=$?
check "$rc" "改変検知時も exit 0 を返すこと (warn-only、got $rc)"
grep -q '\[hooks-integrity\]' <<<"$out"
check "$?" "改変時に警告ラベルを出すこと"
git -C "$FIXTURE" checkout -q -- agents/hooks/sample.sh

# --- 4. 監視対象パスごとの検知 (追跡ファイルの改変 / 未追跡ファイルの追加) ---
# 「変更を作る → 検知される → 元に戻す」の 3 手順は対象が違うだけなので共通化する。
assert_detects() {
  # $1=repo 相対パス, $2=tracked (追跡ファイルの改変) | untracked (未追跡ファイルの追加)
  local rel="$1" kind="$2" detected label
  if [ "$kind" = "tracked" ]; then label="改変"; else label="追加"; fi
  printf 'tampered\n' >> "$FIXTURE/$rel"
  detected=$(run_hook "$FIXTURE")
  grep -q -- "$rel" <<<"$detected"
  check "$?" "${rel} の${label}を検知すること"
  if [ "$kind" = "tracked" ]; then
    git -C "$FIXTURE" checkout -q -- "$rel"
  else
    rm -f "${FIXTURE:?}/$rel"
  fi
}

assert_detects "agents/hooks/sample.sh" tracked
assert_detects "codex/hooks/injected.sh" untracked
assert_detects "codex/hooks.json" tracked
assert_detects "claude/settings.json" tracked

# --- 5. symlink が実体ファイルに置換された場合 (typechange) を検知する ---
rm -f "$FIXTURE/claude/hooks/sample.sh"
printf 'echo replaced\n' > "$FIXTURE/claude/hooks/sample.sh"
out=$(run_hook "$FIXTURE")
grep -q 'claude/hooks/sample.sh' <<<"$out"
check "$?" "symlink の実体ファイル置換 (typechange) を検知すること"
git -C "$FIXTURE" checkout -q -- claude/hooks/sample.sh

# --- 6. git repo でないディレクトリでは fail-open ---
mkdir -p "$WORK/notrepo"
out=$(run_hook "$WORK/notrepo"); rc=$?
check "$rc" "git repo 外で exit 0 (fail-open、got $rc)"
check_empty "$out" "git repo 外で出力が空であること"

# --- 7. 存在しないパスでも fail-open ---
out=$(run_hook "$WORK/missing"); rc=$?
check "$rc" "存在しない repo パスで exit 0 (got $rc)"
check_empty "$out" "存在しない repo パスで出力が空であること"

# --- 8. 配線: claude/hooks/ からの symlink が正本に解決される ---
LINK="$REPO_ROOT/claude/hooks/hooks-integrity-warn.sh"
check_cmd "claude/hooks/hooks-integrity-warn.sh が symlink であること" [ -L "$LINK" ]
if [ -L "$LINK" ]; then
  target=$(readlink "$LINK")
  resolved=$(cd "$(dirname "$LINK")" && cd "$(dirname "$target")" && pwd -P)/$(basename "$target")
  check_cmd "symlink が agents/hooks/hooks-integrity-warn.sh に解決されること (got ${resolved})" [ "$resolved" = "$HOOK" ]
fi

# --- 9. 配線: settings.json の SessionStart に startup|resume エントリがある ---
if command -v jq >/dev/null 2>&1; then
  found=$(jq -r '
    .hooks.SessionStart[]
    | select(.matcher | test("startup"))
    | .hooks[].command
  ' "$REPO_ROOT/claude/settings.json" 2>/dev/null | grep -c 'hooks-integrity-warn.sh' || true)
  check_cmd "settings.json の SessionStart(startup) が hooks-integrity-warn.sh を呼ぶこと" [ "$found" -ge 1 ]
fi

# --- 10. 配線: run-gate.sh から呼ばれている ---
grep -q 'hooks-integrity-warn.sh' "$REPO_ROOT/tests/run-gate.sh"
check "$?" "tests/run-gate.sh が hooks-integrity-warn.sh を呼ぶこと"

# --- 11. 網羅性: 実際に配線されている hook 実装がすべて監視対象に載っているか ---
# 監視対象はハードコード列挙なので、配線 (settings.json / hooks.json の command)
# から drift しうる。warn-only ゆえ漏れても静かに検知されなくなるだけなので、
# ここで pin しておく (この repo には同型の「対更新漏れ」の前歴がある)。
if command -v jq >/dev/null 2>&1; then
  watched=$(bash "$HOOK" --list-watched)
  # hooks/ 配下だけでなく statusLine のような ~/.claude 直下の実行ファイルも拾う
  # (hooks/ に限定すると watch list に claude/hooks がある限り必ず通る
  # トートロジーになり、drift を検出できない)。
  wired=$(
    {
      jq -r '.hooks | to_entries[] | .value[].hooks[].command' "$REPO_ROOT/claude/settings.json"
      jq -r '.statusLine.command // empty' "$REPO_ROOT/claude/settings.json"
      jq -r '.hooks | to_entries[] | .value[].hooks[].command' "$REPO_ROOT/codex/hooks.json"
    } 2>/dev/null \
      | grep -oE '\$HOME/\.(claude|codex)/[A-Za-z0-9._/-]+\.(sh|json)' \
      | sed -E 's#^\$HOME/\.([a-z]+)/#\1/#' \
      | sort -u
  )
  check_cmd "settings.json / hooks.json から配線済み hook を抽出できること" [ -n "$wired" ]
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    covered=0
    while IFS= read -r w; do
      case "$rel" in
        "$w"|"$w"/*) covered=1; break ;;
      esac
    done <<EOF
$watched
EOF
    check_cmd "配線済みの ${rel} が監視対象に含まれること" [ "$covered" = "1" ]
  done <<EOF
$wired
EOF
fi

# --- 12. cwd 非依存の repo 導出 (HOOKS_INTEGRITY_REPO 無し・symlink 経由・別 cwd) ---
# 本番の起動形態はこの経路 (SessionStart から `bash "$HOME/.claude/hooks/..."`)。
# 上のケースは全て HOOKS_INTEGRITY_REPO を渡すため、BASH_SOURCE → pwd -P →
# rev-parse の導出そのものは一度も通っていない。ここで実経路を 1 回踏む。
derived=$(cd "$WORK" && env -u HOOKS_INTEGRITY_REPO bash "$REPO_ROOT/claude/hooks/hooks-integrity-warn.sh" 2>&1)
rc=$?
check "$rc" "別 cwd + symlink 経由の起動で exit 0 (got $rc)"
# この作業ツリー自身が dirty かどうかで期待値が変わるため、dotfiles repo を
# 見に行けていること (= repo 内パスを出す or clean で無出力) だけを検査する。
if [ -n "$derived" ]; then
  grep -qE '(agents|claude|codex)/' <<<"$derived"
  check "$?" "導出した repo の監視対象パスを報告すること (got: $derived)"
else
  # clean のときは自前導出が失敗しても無出力になり区別がつかないので、
  # 監視対象を強制的に dirty にして再確認する。
  printf 'probe\n' > "$PROBE"
  derived=$(cd "$WORK" && env -u HOOKS_INTEGRITY_REPO bash "$REPO_ROOT/claude/hooks/hooks-integrity-warn.sh" 2>&1)
  rm -f "$PROBE"
  grep -q 'hooks-integrity-probe' <<<"$derived"
  check "$?" "clean な作業ツリーでも自前導出が dotfiles repo を指すこと"
fi

echo "hooks-integrity: ${pass} passed, ${fail} failed"
[ "$fail" = 0 ] || exit 1
