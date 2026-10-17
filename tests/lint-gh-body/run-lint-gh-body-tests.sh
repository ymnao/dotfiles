#!/usr/bin/env bash
# -e を外している: hook は block を exit 2 で表すので、`|| rc=$?` で受ける
set -uo pipefail

# lint-gh-body.sh (issue #452) のシナリオテスト。
# textlint は PATH に依存せず LINT_GH_BODY_TEXTLINT で偽物に差し替える。偽物は
# 本文に NG があれば exit 1、FATAL があれば exit 2 で終わり、呼ばれたことを
# CALLED に記録する。止めた記録はケースごとに別の state dir に置く
# (2 回目は通す、のケースだけ同じ state dir を使い回す)。
#
# 実物の textlint (node_modules) が入っていれば、設定ファイルとプリセットの
# 組み合わせも 2 ケース確かめる。CI の test job は pnpm install をしないので skip する。
#
# 使い方: run-lint-gh-body-tests.sh
#   環境変数 HOOK_PATH で hook の場所を上書きできる
#   (デフォルト: <リポジトリルート>/agents/hooks/lint-gh-body.sh)
#
# 依存: bash 3.2+ / jq / git (リポジトリルート解決のみ)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
HOOK="${HOOK_PATH:-$REPO_ROOT/agents/hooks/lint-gh-body.sh}"

[ -f "$HOOK" ] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }

BASE="$(mktemp -d "${TMPDIR:-/tmp}/lint-gh-body-tests.XXXXXX")"
cleanup() { [ -n "${BASE:-}" ] && rm -rf "$BASE"; }
trap cleanup EXIT

FAKE="$BASE/fake-textlint"
CALLED="$BASE/called"
cat >"$FAKE" <<EOF
#!/bin/sh
: > "$CALLED"
body=\$(cat)
case "\$body" in
  *FATAL*) echo "fatal" >&2; exit 2 ;;
  *NORULES*) echo "== No rules found, textlint hasn't done anything =="; exit 1 ;;
  *NG*) echo "body.md:1:1: fake violation [Error/fake-rule]"; exit 1 ;;
esac
exit 0
EOF
chmod +x "$FAKE"

WORK="$BASE/work"
mkdir -p "$WORK/dir with space"
printf 'NG 本文\n' > "$WORK/ng.md"
printf 'NG 別パス\n' > "$WORK/ng2.md"
printf 'NG 本文\n' > "$WORK/ng-copy.md"
printf 'NG 相対\n' > "$WORK/rel.md"
printf 'NG 空白\n' > "$WORK/dir with space/ng.md"
printf '問題のない本文\n' > "$WORK/ok.md"
printf 'FATAL\n' > "$WORK/fatal.md"
printf 'NORULES\n' > "$WORK/norules.md"

pass=0
fail=0

# record <name> <command...>: コマンドの成否で pass / fail を数える
record() {
  local name="$1"
  shift
  if "$@"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $name"
    return 1
  fi
}

# 本番は ~/.claude/hooks や ~/.codex/hooks の dir symlink 越しに起動されるので、同じ形を作る
mkdir -p "$BASE/home"
ln -s "$(dirname "$HOOK")" "$BASE/home/hooks"
LINKED_HOOK="$BASE/home/hooks/$(basename "$HOOK")"

# run_case <name> <expect_rc> <state_dir> <command> [cwd] [textlint] [hook]
run_case() {
  local name="$1" expect="$2" state="$3" cmd="$4" cwd="${5-$WORK}" tl="${6-$FAKE}" hook="${7-$HOOK}"
  local payload rc=0 out err
  payload=$(jq -n --arg c "$cmd" --arg cwd "$cwd" --arg s "test-session" \
    '{tool_name: "Bash", tool_input: {command: $c}, cwd: $cwd, session_id: $s}')
  rm -f "$CALLED"
  out=$(cd "$BASE" && printf '%s' "$payload" \
    | LINT_GH_BODY_TEXTLINT="$tl" LINT_GH_BODY_STATE_DIR="$BASE/state-$state" \
      bash "$hook" 2>"$BASE/stderr") || rc=$?
  err=$(cat "$BASE/stderr")
  record "$name (expected exit $expect, got $rc)" test "$rc" -eq "$expect" \
    || printf '%s\n' "$err" | sed 's/^/    /'
  LAST_OUT="$out"
  LAST_ERR="$err"
}

# --- 止める -------------------------------------------------------------
run_case "pr create --body-file で違反あり → block" 2 a "gh pr create --title t --body-file \"$WORK/ng.md\""
# LAST_ERR は日本語を含むので、バイト列として ASCII の固定文字列を探す
record "block 時の stderr に textlint の指摘が載る" env LC_ALL=C grep -qF 'fake violation' <<< "$LAST_ERR"
record "block 時の stderr に本文のパスが載る" env LC_ALL=C grep -qF "$WORK/ng.md" <<< "$LAST_ERR"
# codex は stdout が { / [ で始まると本文を捨てる。何も出さないことを pin する
record "block 時の stdout は空" test -z "$LAST_OUT"

run_case "2 回目の同じパスは通す" 0 a "gh pr create --title t --body-file \"$WORK/ng.md\""
record "2 回目は textlint を呼ばない" test ! -e "$CALLED"
run_case "同じ内容の別パスは通す" 0 a "gh issue comment 1 -F \"$WORK/ng-copy.md\""
run_case "違う内容の別パスは止める" 2 a "gh issue comment 1 -F \"$WORK/ng2.md\""

printf 'NG 直す前\n' > "$WORK/edit.md"
run_case "直す前の本文 → block" 2 p "gh pr create --title t --body-file \"$WORK/edit.md\""
printf 'NG 一部だけ直した\n' > "$WORK/edit.md"
run_case "同じパスで内容を変えた 2 回目は通す" 0 p "gh pr create --title t --body-file \"$WORK/edit.md\""

run_case "dir symlink 越しの起動 → block" 2 sym "gh pr create --title t --body-file \"$WORK/ng.md\"" "$WORK" "$FAKE" "$LINKED_HOOK"
run_case "issue create -F で違反あり → block" 2 b "gh issue create -t t -F \"$WORK/ng.md\""
run_case "--body-file=<path> の形 → block" 2 c "gh pr edit 1 --body-file=\"$WORK/ng.md\""
run_case "単一引用のパス → block" 2 d2 "gh pr comment 1 --body-file '$WORK/ng.md'"
run_case "空白を含むパスの二重引用 → block" 2 d "gh pr review 1 --comment --body-file \"$WORK/dir with space/ng.md\""
run_case "相対パスは payload の cwd から解決 → block" 2 e "gh pr comment 1 --body-file rel.md"
run_case "2 つ目の gh 呼び出しも見る → block" 2 f "gh pr comment 1 --body-file \"$WORK/ok.md\" && gh issue create -t t -F \"$WORK/ng.md\""

# --- 通す ---------------------------------------------------------------
run_case "違反なし → allow" 0 g "gh pr create --title t --body-file \"$WORK/ok.md\""
run_case "指摘の行が無い exit 1 (ルール未読込) は通す" 0 h2 "gh pr create --title t --body-file \"$WORK/norules.md\""
# state dir の位置に普通のファイルを置いて mkdir を失敗させる
: > "$BASE/state-ro"
run_case "止めた記録を書けないなら通す" 0 ro "gh pr create --title t --body-file \"$WORK/ng.md\""
run_case "textlint の異常終了 (exit 2) は通す" 0 h "gh pr create --title t --body-file \"$WORK/fatal.md\""
run_case "gh api -F はフィールド指定なので見ない" 0 i "gh api repos/o/r/issues -F body=@\"$WORK/ng.md\""
record "gh api では textlint を呼ばない" test ! -e "$CALLED"
run_case "gh 以外の -F (git commit) は見ない" 0 j "git commit -F \"$WORK/ng.md\""
run_case "変数展開のパスは解決しない → allow" 0 k "gh pr create --title t --body-file \$TMPDIR/ng.md"
run_case "存在しないファイル → allow" 0 l "gh pr create --title t --body-file \"$WORK/missing.md\""
run_case "textlint が無い → allow" 0 m "gh pr create --title t --body-file \"$WORK/ng.md\"" "$WORK" "$BASE/no-such-textlint"

# --- 実物の textlint (任意) -------------------------------------------
REAL="$REPO_ROOT/node_modules/.bin/textlint"
if [ -x "$REAL" ]; then
  printf -- '- **追加**: 革新的な仕組みです ✅\n- **削除**: 完璧なテストです 🚀\n' > "$WORK/ai.md"
  printf 'hook を追加した。本文の検査に使う。\n' > "$WORK/plain.md"
  run_case "実物: AI 文体の本文 → block" 2 real-a "gh pr create --title t --body-file \"$WORK/ai.md\"" "$WORK" "$REAL"
  run_case "実物: allows の語だけの本文 → allow" 0 real-b "gh pr create --title t --body-file \"$WORK/plain.md\"" "$WORK" "$REAL"
else
  echo "SKIP: 実物の textlint が無い ($REAL)"
fi

echo "lint-gh-body: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
