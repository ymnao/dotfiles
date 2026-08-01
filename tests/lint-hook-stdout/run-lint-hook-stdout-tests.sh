#!/usr/bin/env bash
# linter の exit code を検査対象として自分で扱うため `set -e` は付けない
# (`-e` だと違反あり = exit 1 の時点でスイートごと落ちる)。
set -uo pipefail

# scripts/lint-hook-stdout.sh の回帰テスト (issue #240)。
#
# 使い方: run-lint-hook-stdout-tests.sh
#   環境変数 LINT_PATH で linter の場所を上書きできる
#   (デフォルト: <リポジトリルート>/scripts/lint-hook-stdout.sh)
#
# 依存: bash 3.2+ / git
#
# 検査の重点は 2 つ (claude/rules/shell.md):
#   - **効き目の実測**: 「守りたい状態」= 実物の hook が旧ラベルに戻った状態を
#     実際に作って検出できることを見る (マッチしない入力を試すだけでは足りない)。
#   - **受理側の広さ**: stderr 送りの除外が広すぎないか、symlink 除外が
#     二重検査だけを落として本体検査まで落としていないかを、通ってしまうと
#     困る入力を自分で構成して確かめる。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
LINT="${LINT_PATH:-$REPO_ROOT/scripts/lint-hook-stdout.sh}"

if [ ! -f "$LINT" ]; then
  echo "ERROR: linter not found: $LINT (LINT_PATH で上書き可)" >&2
  exit 1
fi

BASE="$(mktemp -d "${TMPDIR:-/tmp}/lint-hook-stdout-tests.XXXXXX")"
cleanup() { [ -n "${BASE:-}" ] && rm -rf "$BASE"; }
trap cleanup EXIT

pass=0
fail=0
ran=0

# 期待実行ケース数は**独立した定数**として持つ (ケース定義から導出しない。
# 導出するとケースが消えたとき下限も一緒に下がって検出が無効化される)。
EXPECTED_CASES=44

# run_lint <fixture root> — 出力は $OUT に書き、exit code は $rc に入れる。
# コマンド置換で受けると subshell になり rc が呼び出し元に返らないため、
# 出力はファイル経由にする。
OUT="$BASE/lint-out.txt"
rc=0
run_lint() {
  LINT_HOOK_STDOUT_ROOT="$1" bash "$LINT" >"$OUT" 2>&1
  rc=$?
}

check_detect() {
  # $1=ケース名 $2=fixture root $3=期待 exit code (0=clean / 1=違反あり)
  local name="$1" root="$2" want="$3"
  run_lint "$root"
  check_bool "$name" "expected exit=${want} got=${rc}" [ "$rc" = "$want" ]
}

# check_bool <ケース名> <FAIL 時の説明> <判定コマンド...>
# ran/pass/fail の更新を 1 箇所に集約する ($ran は EXPECTED_CASES との突き合わせに
# 使うため、加算をケースごとに手書きすると書き忘れで検出力が静かに落ちる)。
check_bool() {
  local name="$1" detail="$2"
  shift 2
  ran=$((ran + 1))
  if "$@"; then
    pass=$((pass + 1))
  else
    echo "FAIL ${name}: ${detail}"
    [ -s "$OUT" ] && cat "$OUT"
    fail=$((fail + 1))
  fi
}

# fixture root を 1 つ作る。$2 以降は「相対パス:本文ファイル」ではなく
# ここでは呼び出し側が直接ファイルを書く方式にする。
new_root() {
  local root="$BASE/$1"
  mkdir -p "$root/agents/hooks" "$root/claude/hooks" "$root/codex/hooks"
  printf '%s' "$root"
}

# form_case <ケース名> <期待 exit code> — stdin を 1 本の hook として置いて lint する。
# 「1 形 = 1 fixture」にして、どの形で落ちたかがケース名から分かるようにする。
form_case() {
  local name="$1" want="$2"
  local root="$BASE/form-$name"
  mkdir -p "$root/agents/hooks"
  cat >"$root/agents/hooks/x.sh"
  check_detect "form-${name}" "$root" "$want"
}

# check_report <ケース名> <期待する報告行> — 直前の run_lint の出力に完全一致行があるか。
# exit code だけを見ると、別経路で偶然 1 件報告されても pass してしまう。
check_report() {
  # 報告行はファイル名と行番号のバイト一致で見る (照合順序を持ち込まないため
  # LC_ALL=C 固定。env 経由なのは check_bool が "$@" をそのまま実行するため)
  check_bool "$1" "報告行 '$2' が無い" env LC_ALL=C grep -qF "$2" "$OUT"
}

# ---------------------------------------------------------------------------
# 1. clean: 違反なし fixture は exit 0 かつ無出力
# ---------------------------------------------------------------------------
root=$(new_root clean)
cat >"$root/agents/hooks/ok.sh" <<'SH'
#!/usr/bin/env bash
echo "session-compact-context: ラベル"
printf '%s\n' "$x"
cat <<EOF
ラベル: 本文
EOF
SH
check_detect "clean-exit" "$root" 0
run_lint "$root"
check_bool "clean-silent" "違反なしなのに出力がある" [ ! -s "$OUT" ]

# ---------------------------------------------------------------------------
# 2. mutation: heredoc 本文の先頭が [ (issue #240 の実ケースの形)
# ---------------------------------------------------------------------------
root=$(new_root mut-heredoc)
cat >"$root/agents/hooks/bad.sh" <<'SH'
#!/usr/bin/env bash
cat <<EOF
[session-compact-context] リマインダー
EOF
SH
check_detect "mutation-heredoc" "$root" 1
check_report "mutation-heredoc-report" "agents/hooks/bad.sh:3: heredoc-json-prefix"

# ---------------------------------------------------------------------------
# 3. mutation: echo のリテラルが [ 始まり
# ---------------------------------------------------------------------------
root=$(new_root mut-echo)
printf '%s\n' '#!/usr/bin/env bash' "echo '[x] メッセージ'" >"$root/agents/hooks/bad.sh"
check_detect "mutation-echo" "$root" 1
check_report "mutation-echo-report" "agents/hooks/bad.sh:2: stdout-json-prefix"

# ---------------------------------------------------------------------------
# 4. mutation: printf の第 1 引数が { 始まり (JSON リテラル)
# ---------------------------------------------------------------------------
root=$(new_root mut-printf-json)
printf '%s\n' '#!/usr/bin/env bash' 'printf '"'"'{"a":1}\n'"'"'' >"$root/agents/hooks/bad.sh"
check_detect "mutation-printf-json" "$root" 1

# ---------------------------------------------------------------------------
# 5. mutation: printf の**第 2 引数**が [ 始まり (フォーマット文字列の次)
#    受理側の広さ検査: 第 1 引数だけ見る実装だとここで素通りする
# ---------------------------------------------------------------------------
root=$(new_root mut-printf-arg2)
printf '%s\n' '#!/usr/bin/env bash' 'printf '"'"'%s\n'"'"' '"'"'[x]'"'"'' >"$root/agents/hooks/bad.sh"
check_detect "mutation-printf-second-arg" "$root" 1

# ---------------------------------------------------------------------------
# 5b. 受理側の広さ: いずれも「stdout に JSON 始まりが出る」形。code-reviewer が
#     実測で素通りを確認した 14 形の回帰ケース (PR のレビュー 1 周目)。
#     前半 2 形 (heredoc 誤爆) は**そのファイルの残り全部が無検査になる**型で、
#     この linter が防ごうとしている「静かに壊れる」構図と同じ壊れ方をする。
# ---------------------------------------------------------------------------
form_case "tab-heredoc" 1 <<'SH'
#!/usr/bin/env bash
cat <<-EOF
	[tab-indented]
	EOF
SH

form_case "here-string" 1 <<'SH'
#!/usr/bin/env bash
grep -q foo <<<somevalue
echo '[after-here-string]'
SH

form_case "trailing-comment-lt" 1 <<'SH'
#!/usr/bin/env bash
foo=bar   # heredoc (<< EOF) is not used here
echo '[after-trailing-comment]'
SH

form_case "then" 1 <<'SH'
#!/usr/bin/env bash
if [ -n xx ]; then echo '[then-form]'; fi
SH

form_case "case-branch" 1 <<'SH'
#!/usr/bin/env bash
case xx in y) echo '[case-form]' ;; esac
SH

form_case "brace-group" 1 <<'SH'
#!/usr/bin/env bash
{ echo '[brace-group]'; }
SH

form_case "subshell" 1 <<'SH'
#!/usr/bin/env bash
( echo '[subshell]' )
SH

form_case "do-inline" 1 <<'SH'
#!/usr/bin/env bash
for f in a; do echo '[do-inline]'; done
SH

form_case "stderr-mention-in-literal" 1 <<'SH'
#!/usr/bin/env bash
echo "[hint] redirect with >&2 to be safe"
SH

form_case "stderr-mention-in-comment" 1 <<'SH'
#!/usr/bin/env bash
cat <<EOF   # advice: send it to >&2 instead
[heredoc-with-mention]
EOF
SH

form_case "line-continuation" 1 <<'SH'
#!/usr/bin/env bash
printf '%s\n' \
  '[continued-arg]'
SH

form_case "backslash-terminator" 1 <<'SH'
#!/usr/bin/env bash
cat <<\EOF
[backslash-term]
EOF
SH

# issue #215 が「守りたい状態」と定義した形 — 先頭が改行で、その次が JSON 始まり
form_case "leading-newline-escape" 1 <<'SH'
#!/usr/bin/env bash
printf '\n{"a":1}\n'
SH

form_case "leading-space" 1 <<'SH'
#!/usr/bin/env bash
echo ' [x] warn'
SH

# 引用の中の `<<` は heredoc ではない (mask が誤爆すると後続が無検査になる)
form_case "quoted-lt-is-not-heredoc" 0 <<'SH'
#!/usr/bin/env bash
echo "shift << amount is fine"
echo "ok"
SH

# ---------------------------------------------------------------------------
# 5c. codex-review (shell-senior) と code-reviewer 2 周目が実測で挙げた形。
#     前半 4 形は「解析が `<<` を誤検出してファイル全体が無検査になる」型で、
#     閉じない heredoc として **unclosed-heredoc** で必ず表面化させる
#     (無言で緑にすると、この linter 自身が静かに消える)。
# ---------------------------------------------------------------------------
form_case "heredoc-after-echo" 1 <<'SH'
#!/usr/bin/env bash
echo '[before-heredoc]'; cat <<EOF
body
EOF
SH

form_case "ansi-c-quote" 1 <<'SH'
#!/usr/bin/env bash
printf $'{"a":1}\n'
SH

form_case "var-assign-prefix" 1 <<'SH'
#!/usr/bin/env bash
LC_ALL=C echo '[x]'
SH

form_case "arith-shift" 1 <<'SH'
#!/usr/bin/env bash
x=$((1 << 3))
echo '[after-shift]'
SH

form_case "multiline-string-lt" 1 <<'SH'
#!/usr/bin/env bash
usage="usage:
  cmd << EOF"
echo '[after-multiline-string]'
SH
# 報告は「`<<` を拾った行」= 引用の 2 行目 (3 行目)。ここがずれると
# 追跡開始位置の取り違えを見逃す
check_report "multiline-string-lt-unclosed" "agents/hooks/x.sh:3: unclosed-heredoc"

form_case "comment-after-semicolon" 1 <<'SH'
#!/usr/bin/env bash
echo ok;#<< EOF
echo '[after-inline-comment]'
SH

form_case "heredoc-stderr-other-segment" 1 <<'SH'
#!/usr/bin/env bash
{ echo warn >&2; cat <<EOF; }
[should-be-flagged]
EOF
SH

# --- 以下は非検出が正しい形 (受理側を広げすぎていないかの対照) ---

form_case "ok-arith-shift" 0 <<'SH'
#!/usr/bin/env bash
x=$((1 << 3))
echo "ok ${x}"
SH

form_case "ok-stderr-variants" 0 <<'SH'
#!/usr/bin/env bash
echo '[x]' > /dev/stderr
echo '[y]' >& 2
SH

form_case "ok-heredoc-to-stderr" 0 <<'SH'
#!/usr/bin/env bash
cat >&2 <<EOF
[stderr body]
EOF
SH

# ---------------------------------------------------------------------------
# 6. 効き目の実測: **実物の session-compact-context.sh** を fixture に置き、
#    ラベルだけ旧 `[session-compact-context]` に戻した mutant を検出できるか。
#    mutation は 1 回に 1 変数だけ変える。置換が実際にコード行に当たったことを
#    diff で確認する (この repo はコメントに同じ字面が出るため空振りしやすい)。
# ---------------------------------------------------------------------------
root=$(new_root mut-real)
real="$REPO_ROOT/agents/hooks/session-compact-context.sh"
cp "$real" "$root/agents/hooks/session-compact-context.sh"
check_detect "real-hook-unmutated-clean" "$root" 0

mutant="$root/agents/hooks/session-compact-context.sh"
# 日本語を含む置換なので LC_ALL=C でバイト一致に固定する (BSD awk の照合は
# ロケール依存で、UTF-8 ロケールでは同一に見える別バイト列を取り違えうる)
LC_ALL=C awk '{ sub(/^session-compact-context: コンパクション後/, "[session-compact-context] コンパクション後"); print }' \
  "$mutant" >"$mutant.new" && mv "$mutant.new" "$mutant"
check_bool "real-hook-mutation-applied" "置換が空振りした (コード行に当たっていない)" \
  grep -q '^\[session-compact-context\]' "$mutant"
check_detect "real-hook-mutated-detected" "$root" 1

# ---------------------------------------------------------------------------
# 7. 受理側の広さ: stderr 送り (>&2) は非検出。ただし stdout にも残る形
#    (`| tee`) は検出したままであること
# ---------------------------------------------------------------------------
root=$(new_root accept-stderr)
cat >"$root/agents/hooks/stderr-only.sh" <<'SH'
#!/usr/bin/env bash
echo "[x] 警告" >&2
printf '{"a":1}\n' >&2
SH
check_detect "accept-stderr-not-flagged" "$root" 0

root=$(new_root accept-tee)
cat >"$root/agents/hooks/tee.sh" <<'SH'
#!/usr/bin/env bash
echo "[x] 警告" | tee /dev/null
SH
check_detect "stdout-via-tee-flagged" "$root" 1

# ---------------------------------------------------------------------------
# 8. symlink: 実体は検査され、symlink 経由の二重計上はしない
# ---------------------------------------------------------------------------
root=$(new_root symlink)
printf '%s\n' '#!/usr/bin/env bash' "echo '[x]'" >"$root/agents/hooks/bad.sh"
ln -s ../../agents/hooks/bad.sh "$root/claude/hooks/bad.sh"
run_lint "$root"
hits=$(grep -c 'stdout-json-prefix' "$OUT")
check_bool "symlink-single-count" "expected 1 hit got ${hits}" [ "$hits" = "1" ]

# ---------------------------------------------------------------------------
# 9. codex 固有 hook のディレクトリも走査対象であること
# ---------------------------------------------------------------------------
root=$(new_root codex-dir)
printf '%s\n' '#!/usr/bin/env bash' "echo '[x]'" >"$root/codex/hooks/bad.sh"
check_detect "codex-hooks-scanned" "$root" 1

# ---------------------------------------------------------------------------
# 9b. 走査 0 件はゲートが消えた状態なので fail させる (緑で通すと、hook
#     ディレクトリの改名や root の指定ミスで検査が無くなったことに気付けない)
# ---------------------------------------------------------------------------
check_detect "zero-scan-fails" "$BASE/does-not-exist" 1

root=$(new_root renamed-dir)
mv "$root/agents/hooks" "$root/agents/hook"
printf '%s\n' '#!/usr/bin/env bash' "echo '[x]'" >"$root/agents/hook/bad.sh"
rmdir "$root/claude/hooks" "$root/codex/hooks"
check_detect "renamed-dir-fails" "$root" 1

# ---------------------------------------------------------------------------
# 10. 実リポジトリ: override 無しで exit 0 (end-to-end)
# ---------------------------------------------------------------------------
(cd "$REPO_ROOT" && bash "$LINT" >"$OUT" 2>&1)
check_bool "real-repo-clean" "実リポジトリで違反が出ている" [ ! -s "$OUT" ]

echo "----"
echo "lint-hook-stdout tests: $pass passed, $fail failed"
if [ "$ran" != "$EXPECTED_CASES" ]; then
  echo "FAIL case-count: expected ${EXPECTED_CASES} cases, ran ${ran} (ケースの取りこぼし)"
  exit 1
fi
[ "$fail" = 0 ] || exit 1
exit 0
