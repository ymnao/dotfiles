#!/usr/bin/env bash
#
# agents/hooks/hooks-integrity-warn.sh の回帰テスト (issue #207)。
#
# 検証内容:
#   1. 検知ロジック — 監視対象パスの未コミット改変だけを警告し、対象外の
#      変更や clean な repo では何も出さない。常に exit 0 (warn-only)
#   2. fail-open — git 不在 / repo 外 / 存在しないパスで黙って exit 0
#   3. 配線 — claude/hooks/ からの symlink・settings.json の SessionStart
#      エントリ・tests/run-gate.sh と Makefile からの呼び出しが揃っている
#
# すべて $TMPDIR の一時 git repo に対して実行する。実 dotfiles 作業ツリーは
# 一切変更しない (以前は cwd 非依存の導出を実 repo で確認していたが、中断時に
# 未追跡ファイルが残って SessionStart 警告を汚染するため fixture 方式に変更)。

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

# git hook 等から起動された場合、これらを継承すると fixture の git 操作が
# 呼び出し元 repo の index / object DB を触ってしまう。隔離を確実にする。
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_COMMON_DIR GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)" || exit 1
[ -n "$REPO_ROOT" ] || { echo "FAIL: repo root を解決できません"; exit 1; }
HOOK="$REPO_ROOT/agents/hooks/hooks-integrity-warn.sh"

# jq が無いと配線 assert が丸ごとスキップされて「0 failed」で成功扱いになるため、
# 黙ってカバレッジを落とさず必須依存として扱う (make test も jq を必須にしている)。
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq 未インストール (このテストは jq を必須とする)"; exit 1; }

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
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

FIXTURE="$WORK/repo"
mkdir -p "$FIXTURE/agents/hooks" "$FIXTURE/claude/hooks" "$FIXTURE/codex/hooks" "$FIXTURE/.claude"
printf 'echo base\n' > "$FIXTURE/agents/hooks/sample.sh"
printf '{}\n' > "$FIXTURE/codex/hooks.json"
printf '{}\n' > "$FIXTURE/claude/settings.json"
printf 'echo statusline\n' > "$FIXTURE/claude/statusline.sh"
printf 'model = "x"\n' > "$FIXTURE/codex/config.toml"
printf 'make gate\n' > "$FIXTURE/.claude/stop-gate.conf"
printf '{}\n' > "$FIXTURE/.claude/settings.json"
printf 'readme\n' > "$FIXTURE/README.md"
# 本番と同じく claude/hooks/ は agents/hooks/ への相対 symlink にしておく
# (symlink が実体ファイルに置換される typechange も検知対象に入るため)。
ln -s ../../agents/hooks/sample.sh "$FIXTURE/claude/hooks/sample.sh"
# cwd 非依存の repo 導出 (ケース 12) を fixture 内で踏むため、hook 本体と
# 本番相当の相対 symlink を fixture にも置く。
cp "$HOOK" "$FIXTURE/agents/hooks/hooks-integrity-warn.sh"
ln -s ../../agents/hooks/hooks-integrity-warn.sh "$FIXTURE/claude/hooks/hooks-integrity-warn.sh"

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

# --- 3. 改変時に警告ラベルを出し、exit 0 を保つ ---
printf 'echo tampered\n' >> "$FIXTURE/agents/hooks/sample.sh"
out=$(run_hook "$FIXTURE"); rc=$?
check "$rc" "改変検知時も exit 0 を返すこと (warn-only、got $rc)"
grep -q '\[hooks-integrity\]' <<<"$out"
check "$?" "改変時に警告ラベルを出すこと"
git -C "$FIXTURE" checkout -q -- agents/hooks/sample.sh

# --- 4. 監視対象パスごとの検知 ---
# 「変更を作る → 検知される → 元に戻す」の手順は対象と変更種別が違うだけなので共通化する。
assert_detects() {
  # $1=repo 相対パス
  # $2=tracked (内容改変) | untracked (新規追加) | deleted (削除) | staged (git add 済み)
  local rel="$1" kind="$2" detected label
  case "$kind" in
    tracked) label="改変"; printf 'tampered\n' >> "$FIXTURE/$rel" ;;
    untracked) label="追加"; printf 'injected\n' > "$FIXTURE/$rel" ;;
    deleted) label="削除"; rm -f "${FIXTURE:?}/$rel" ;;
    staged) label="ステージ済み変更"
      printf 'tampered\n' >> "$FIXTURE/$rel"
      git -C "$FIXTURE" add -- "$rel"
      ;;
  esac
  detected=$(run_hook "$FIXTURE")
  grep -q -- "$rel" <<<"$detected"
  check "$?" "${rel} の${label}を検知すること"
  if [ "$kind" = "untracked" ]; then
    rm -f "${FIXTURE:?}/$rel"
  else
    git -C "$FIXTURE" reset -q -- "$rel"
    git -C "$FIXTURE" checkout -q -- "$rel"
  fi
}

assert_detects "agents/hooks/sample.sh" tracked
assert_detects "codex/hooks/injected.sh" untracked
assert_detects "codex/hooks.json" tracked
assert_detects "claude/settings.json" tracked
assert_detects "claude/statusline.sh" tracked
assert_detects "codex/config.toml" tracked
assert_detects ".claude/stop-gate.conf" tracked
assert_detects ".claude/settings.json" tracked
assert_detects "agents/hooks/sample.sh" deleted
assert_detects "codex/hooks.json" staged

# --- 5. symlink が実体ファイルに置換された場合 (typechange) を検知する ---
rm -f "$FIXTURE/claude/hooks/sample.sh"
printf 'echo replaced\n' > "$FIXTURE/claude/hooks/sample.sh"
out=$(run_hook "$FIXTURE")
grep -q 'claude/hooks/sample.sh' <<<"$out"
check "$?" "symlink の実体ファイル置換 (typechange) を検知すること"
git -C "$FIXTURE" checkout -q -- claude/hooks/sample.sh

# --- 6. 21 件以上のとき先頭 20 件に切り詰め、残件数を明示する ---
i=1
while [ "$i" -le 21 ]; do
  printf 'x\n' > "$FIXTURE/codex/hooks/bulk-${i}.sh"
  i=$((i + 1))
done
out=$(run_hook "$FIXTURE"); rc=$?
check "$rc" "21 件の変更でも exit 0 (got $rc)"
grep -q '(21 件)' <<<"$out"
check "$?" "件数は全件 (21 件) を報告すること"
detail_lines=$(grep -c 'codex/hooks/bulk-' <<<"$out")
check_cmd "明細は 20 件に切り詰めること (got ${detail_lines})" [ "$detail_lines" = "20" ]
grep -q '他 1 件' <<<"$out"
check "$?" "切り詰めた残件数を明示すること"
rm -f "${FIXTURE:?}"/codex/hooks/bulk-*.sh

# --- 7. git repo でないディレクトリでは fail-open ---
mkdir -p "$WORK/notrepo"
out=$(run_hook "$WORK/notrepo"); rc=$?
check "$rc" "git repo 外で exit 0 (fail-open、got $rc)"
check_empty "$out" "git repo 外で出力が空であること"

# --- 8. 存在しないパスでも fail-open ---
out=$(run_hook "$WORK/missing"); rc=$?
check "$rc" "存在しない repo パスで exit 0 (got $rc)"
check_empty "$out" "存在しない repo パスで出力が空であること"

# --- 8b. HOOKS_INTEGRITY_REPO 無しで自己パスからも repo を特定できない場合 ---
# 上の fail-open ケースは全て env で repo を渡しているため、rev-parse が失敗する
# 分岐 (hook が git repo 外に置かれている) を通っていない。
mkdir -p "$WORK/orphan"
cp "$HOOK" "$WORK/orphan/hooks-integrity-warn.sh"
out=$(cd "$WORK" && env -u HOOKS_INTEGRITY_REPO bash "$WORK/orphan/hooks-integrity-warn.sh" 2>&1); rc=$?
check "$rc" "repo 外に置かれた hook が exit 0 (fail-open、got $rc)"
check_empty "$out" "repo を特定できないとき出力が空であること"

# --- 9. git が PATH に無い環境でも fail-open ---
mkdir -p "$WORK/emptybin"
printf 'tampered\n' >> "$FIXTURE/agents/hooks/sample.sh"
out=$(PATH="$WORK/emptybin" HOOKS_INTEGRITY_REPO="$FIXTURE" \
  "$BASH" "$HOOK" 2>&1); rc=$?
check "$rc" "git 不在で exit 0 (fail-open、got $rc)"
check_empty "$out" "git 不在で出力が空であること"
git -C "$FIXTURE" checkout -q -- agents/hooks/sample.sh

# --- 10. cwd 非依存の repo 導出 (HOOKS_INTEGRITY_REPO 無し・symlink 経由・別 cwd) ---
# 本番の起動形態はこの経路 (SessionStart から `bash "$HOME/.claude/hooks/..."`)。
# 上のケースは全て HOOKS_INTEGRITY_REPO を渡すため、BASH_SOURCE → pwd -P →
# rev-parse の導出そのものは通っていない。fixture 内で実経路を 1 回踏む。
printf 'echo derived-probe\n' >> "$FIXTURE/agents/hooks/sample.sh"
derived=$(cd "$WORK" && env -u HOOKS_INTEGRITY_REPO \
  bash "$FIXTURE/claude/hooks/hooks-integrity-warn.sh" 2>&1); rc=$?
check "$rc" "別 cwd + symlink 経由の起動で exit 0 (got $rc)"
grep -q 'agents/hooks/sample.sh' <<<"$derived"
check "$?" "自前導出でも fixture repo の変更を検知すること (got: ${derived})"
git -C "$FIXTURE" checkout -q -- agents/hooks/sample.sh

# --- 11. 配線: claude/hooks/ からの symlink が正本に解決される ---
LINK="$REPO_ROOT/claude/hooks/hooks-integrity-warn.sh"
check_cmd "claude/hooks/hooks-integrity-warn.sh が symlink であること" [ -L "$LINK" ]
if [ -L "$LINK" ]; then
  target=$(readlink "$LINK")
  resolved=$(cd "$(dirname "$LINK")" && cd "$(dirname "$target")" && pwd -P)/$(basename "$target")
  check_cmd "symlink が agents/hooks/hooks-integrity-warn.sh に解決されること (got ${resolved})" [ "$resolved" = "$HOOK" ]
fi

# --- 12. 配線: settings.json の SessionStart entry が 3 イベントすべてを拾う ---
matcher=$(jq -r '
  .hooks.SessionStart[]
  | select([.hooks[].command] | any(test("hooks-integrity-warn\\.sh")))
  | .matcher
' "$REPO_ROOT/claude/settings.json")
check_cmd "SessionStart に hooks-integrity-warn.sh の entry が 1 つあること" [ -n "$matcher" ]
# matcher は正規表現なので、部分文字列ではなく「実イベント名に一致するか」で判定する
# (`startup-broken|...` のような実イベントに当たらない値を通さないため)。
matches_re() {
  # $1=検査する文字列, $2=正規表現
  [[ "$1" =~ $2 ]]
}
not_matches_re() {
  ! matches_re "$1" "$2"
}
for ev in startup resume clear; do
  check_cmd "SessionStart matcher が ${ev} に一致すること (got: ${matcher})" \
    matches_re "$ev" "$matcher"
done
# 非対象イベントまで拾う緩い matcher (例: 空文字 / `.*`) になっていないこと
check_cmd "SessionStart matcher が無関係なイベントに一致しないこと (got: ${matcher})" \
  not_matches_re "no-such-event" "$matcher"
# command は完全一致で pin する (パス誤記や余計なコマンドの混入を通さない)
entry=$(jq -r '
  .hooks.SessionStart[].hooks[]
  | select(.command | test("hooks-integrity-warn\\.sh"))
  | "\(.type)|\(.timeout)|\(.command)"
' "$REPO_ROOT/claude/settings.json")
check_cmd "SessionStart entry が type/timeout/command とも期待どおりであること (got ${entry})" \
  [ "$entry" = 'command|10|bash "$HOME/.claude/hooks/hooks-integrity-warn.sh"' ]

# --- 13. 配線: run-gate.sh / Makefile の「コメントでない実行行」から呼ばれている ---
# 単なる grep だと直前の説明コメントに hook 名が残るだけで pass してしまうため、
# 行頭が # でない行に限定して検査する。
grep -vE '^[[:space:]]*(#|@#)' "$REPO_ROOT/tests/run-gate.sh" | grep -q 'hooks-integrity-warn.sh'
check "$?" "tests/run-gate.sh の実行行が hooks-integrity-warn.sh を呼ぶこと"
grep -vE '^[[:space:]]*(#|@#)' "$REPO_ROOT/Makefile" | grep -q 'bash agents/hooks/hooks-integrity-warn.sh'
check "$?" "Makefile の実行行が hooks-integrity-warn.sh を呼ぶこと"

# --- 14. 網羅性: 実際に配線されている実行ファイルがすべて監視対象に載っているか ---
# 監視対象はハードコード列挙なので、配線 (settings.json / hooks.json の command)
# から drift しうる。warn-only ゆえ漏れても静かに検知されなくなるだけなので、
# ここで pin しておく (この repo には同型の「対更新漏れ」の前歴がある)。
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
check_cmd "settings.json / hooks.json から配線済み実行ファイルを抽出できること" [ -n "$wired" ]
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

echo "hooks-integrity: ${pass} passed, ${fail} failed"
[ "$fail" = 0 ] || exit 1
