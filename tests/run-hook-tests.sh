#!/usr/bin/env bash
set -euo pipefail

# Hook 回帰テストランナー。
# 使い方: run-hook-tests.sh [cases.jsonl ...]
#   引数なし: このスクリプトと同階層の hooks/*.cases.jsonl を全実行
#
# ケース形式 (JSONL, 1 行 1 ケース。# 始まりの行と空行はスキップ):
#   {"name":"...","expect":"allow|block","command":"...","reason":"..."}     # Bash 系 (tool_input.command)
#   {"name":"...","expect":"allow|block","tool_input":{...},"reason":"..."}  # Edit/Write/apply_patch 系
#   両方指定された場合は tool_input 側を優先する。
#   hook は隔離 HOME (HOME=$FAKE_HOME) で実行される。実ユーザー環境の
#   $HOME/.codex の有無に依存しないため CI でも同じ結果になる。
#   tool_input / command 内の文字列に `{{HOME}}` が含まれる場合、隔離 HOME に置換する。
#   `{{SYMHOME}}` は「隔離 HOME の .codex を指す (名前に codex を含まない) symlink」に置換する。
#   `{{HOMEPROJLINK}}` は「隔離 HOME 配下のプロジェクトを指す、home 外に置かれた symlink」に置換する。
#   tool_input / command 内の文字列に `{{CWD}}` が含まれる場合、hook 実行時の
#   一時 cwd 実パスに置換される (cwd 内絶対パステスト用)。
#
# raw モード: line が `# raw:` で始まる場合、次行の JSON をそのまま stdin に流し、
#   name/expect を JSON から読まない (壊れた JSON / 非オブジェクト tool_input の fail-safe 検証用)。
#   形式:  # raw:<name>|allow|block
#          <任意の生入力文字列>
#
# PATH モード: 環境変数 HOOK_TEST_STRIP_JQ=1 で jq を PATH から外して hook を実行し、
#   fail-safe (exit 2 = ブロック) を検証する。
#
# 判定:
#   - expect=allow → hook の exit code 0 を期待
#   - expect=block → hook の exit code 2 を期待
#   - claude/hooks/ と codex/hooks/ の両方に同名 hook がある場合は両方に流し、
#     exit code が一致することも検証する (ドリフト検出)
#
# 実行 cwd: mktemp -d した一時ディレクトリ (hook は pwd -P を参照するため、
# テスト結果がリポジトリ cwd に依存しないようにする)。
#
# 依存: bash 3.2+ / jq / git (リポジトリルート解決のみ)
#
# 環境変数 HOOK_DIR: 指定すると claude/codex の両系統ではなく、そのディレクトリの
# hook 単体に対してテストする (例: symlink 切り替え前の agents/hooks/ の検証用)。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# REPO_ROOT は claude/codex 両系統モードでのみ必要。HOOK_DIR モードが
# git 不在・リポジトリ外でも動くよう、git 依存はこの分岐に閉じ込める。
REPO_ROOT=""
if [ -z "${HOOK_DIR:-}" ]; then
  REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 1
fi

# ケースファイル名 → hook スクリプト名の対応。
# verify-ci は早期 exit 経路のみをテストするため名前が異なる。
hook_file_for() {
  case "$1" in
    verify-ci-early-exit) printf '%s' "verify-ci-before-pr.sh" ;;
    *) printf '%s' "$1.sh" ;;
  esac
}

BASEDIR="$(mktemp -d "${TMPDIR:-/tmp}/hook-tests.XXXXXX")"
cleanup() { [ -n "${BASEDIR:-}" ] && rm -rf "$BASEDIR"; }
trap cleanup EXIT

# 一時 cwd (hook の pwd -P 参照対策)
WORKDIR="$BASEDIR/cwd"
mkdir -p "$WORKDIR"

# 隔離 HOME。hook には HOME=$FAKE_HOME を渡して実行する。
# 実 HOME に依存すると、$HOME/.codex が存在しない環境 (CI runner 等) で
# symlink 解決系のケースが落ちる / 実ユーザー環境の状態がテスト結果に混ざる。
# **WORKDIR の外に置くことが重要** — WORKDIR 配下だと cwd 配下の .codex/ と
# みなされ is_protected_project_path 側にマッチしてしまい、home 判定の
# allow ケース (sessions/ 等) が project 判定で block されて意味を失う。
FAKE_HOME="$BASEDIR/home"
mkdir -p "$FAKE_HOME/.codex/sessions"

# {{SYMHOME}}: 名前に codex を含まない symlink が $HOME/.codex を指す状況。
# guard-codex-dir.sh の symlink 解決漏れ (codex-review security 指摘の bypass)
# の回帰を検出する。target を実在ディレクトリにするため隔離 HOME 側を指す。
SYMHOME="$BASEDIR/homelink"
ln -sfn "$FAKE_HOME/.codex" "$SYMHOME"

# {{HOMEPROJLINK}}: home の外にある symlink が $HOME 配下のプロジェクトを指す状況。
# issue #291 の home 配下判定は「home 外は allow」なので、home 外の path 表記から
# home 配下に入る経路が素通りしないことを pin する ({{SYMHOME}} は逆向き
# — home 配下の .codex を home 外の名前で指す形 — なので別ケースが要る)。
HOME_PROJ_LINK="$BASEDIR/projlink"
mkdir -p "$FAKE_HOME/other-project"
ln -sfn "$FAKE_HOME/other-project" "$HOME_PROJ_LINK"

# 対象ケースファイルの決定 (引数なしなら glob。SC2045 回避のため ls は使わない)
if [ "$#" -eq 0 ]; then
  set -- "$SCRIPT_DIR"/hooks/*.cases.jsonl
  if [ ! -f "$1" ]; then
    echo "ERROR: no case files found under $SCRIPT_DIR/hooks/" >&2
    exit 1
  fi
fi

pass=0
fail=0

run_hook() {
  # $1=hook path, $2=input (raw stdin content)。exit code を echo する (0/2 以外もそのまま)
  # HOOK_TEST_STRIP_JQ=1 のとき PATH から jq を除外して hook を実行 (fail-safe 検証)。
  # HOME は隔離 HOME に差し替える (実ユーザー環境からの分離)。
  # CLAUDE_GUARD_MANAGED_SETTINGS は guard-sandbox-exclusions.sh が読む managed
  # settings のパス。HOME / cwd の隔離ではホスト側の
  # /Library/Application Support/ClaudeCode/ を外せないため、存在しないパスを
  # 明示して MDM 管理端末でも CI と同じ結果になるようにする。
  local rc=0
  local nosettings="$BASEDIR/no-managed-settings.json"
  if [ "${HOOK_TEST_STRIP_JQ:-0}" = "1" ]; then
    printf '%s' "$2" | (cd "$WORKDIR" && HOME="$FAKE_HOME" CLAUDE_GUARD_MANAGED_SETTINGS="$nosettings" PATH="$WORKDIR/no-jq-bin:/usr/bin:/bin" bash "$1" >/dev/null 2>&1) || rc=$?
  else
    printf '%s' "$2" | (cd "$WORKDIR" && HOME="$FAKE_HOME" CLAUDE_GUARD_MANAGED_SETTINGS="$nosettings" bash "$1" >/dev/null 2>&1) || rc=$?
  fi
  printf '%s' "$rc"
}

# {{CWD}} を一時 cwd に、{{HOME}} を隔離 HOME に、{{SYMHOME}} / {{HOMEPROJLINK}} を
# 上記 symlink に置換する。
# {{HOME}} は guard-codex-dir.sh の ~/.codex/config.toml 判定 (issue #190) を
# 「実際に tool が渡す絶対パス形」で検証するために必要 — tilde / $HOME 表記だけでは
# normalize_path の展開分岐しか通らず、絶対パス経路が未検証になる。
# sed ではなく bash の文字列置換を使う: パスに & / \ / | が含まれる環境で
# sed の置換文字列が壊れるのを避ける (codex-review shell-senior 指摘)。
substitute_cwd() {
  local s="$1"
  s=${s//\{\{CWD\}\}/$WORKDIR}
  s=${s//\{\{HOME\}\}/$FAKE_HOME}
  s=${s//\{\{SYMHOME\}\}/$SYMHOME}
  s=${s//\{\{HOMEPROJLINK\}\}/$HOME_PROJ_LINK}
  printf '%s' "$s"
}

for cf in "$@"; do
  base=$(basename "$cf" .cases.jsonl)
  hook_name=$(hook_file_for "$base")
  if [ -n "${HOOK_DIR:-}" ]; then
    claude_hook="$HOOK_DIR/$hook_name"
    codex_hook=""
  else
    claude_hook="$REPO_ROOT/claude/hooks/$hook_name"
    codex_hook="$REPO_ROOT/codex/hooks/$hook_name"
  fi
  [ -f "$claude_hook" ] || claude_hook=""
  [ -f "$codex_hook" ] || codex_hook=""
  if [ -z "$claude_hook" ] && [ -z "$codex_hook" ]; then
    echo "ERROR: hook not found for $cf ($hook_name)" >&2
    exit 1
  fi

  echo "==> $base"
  raw_pending=""
  while IFS= read -r line || [ -n "$line" ]; do
    # raw モード: 直前が `# raw:name|expect` で、この行が生入力
    if [ -n "$raw_pending" ]; then
      name=${raw_pending%%|*}
      raw_expect_rest=${raw_pending#*|}
      case "$raw_expect_rest" in
        allow) want=0 ;;
        block) want=2 ;;
        *) echo "FAIL $name: invalid raw expect '$raw_expect_rest'"; fail=$((fail + 1)); raw_pending=""; continue ;;
      esac
      input=$(substitute_cwd "$line")
      raw_pending=""
    else
      case "$line" in
        '') continue ;;
        '# raw:'*)
          raw_pending=${line#'# raw:'}
          continue
          ;;
        '#'*) continue ;;
      esac
      name=$(printf '%s' "$line" | jq -r '.name')
      expect=$(printf '%s' "$line" | jq -r '.expect')
      case "$expect" in
        allow) want=0 ;;
        block) want=2 ;;
        *) echo "FAIL $name: invalid expect '$expect'"; fail=$((fail + 1)); continue ;;
      esac
      # ケース形式: `tool_input` を JSON オブジェクトで直接指定 (Edit/Write/apply_patch 系)。
      # 後方互換で `command` 文字列も受け付け、tool_input.command に組み立てる (Bash 系)。
      # 両方指定された場合は tool_input 側を優先する。
      input=$(printf '%s' "$line" | jq -c '{tool_input: (.tool_input // {command: .command})}')
      input=$(substitute_cwd "$input")
    fi

    got_claude=""
    got_codex=""
    [ -n "$claude_hook" ] && got_claude=$(run_hook "$claude_hook" "$input")
    [ -n "$codex_hook" ] && got_codex=$(run_hook "$codex_hook" "$input")

    ok=1
    [ -n "$got_claude" ] && [ "$got_claude" != "$want" ] && ok=0
    [ -n "$got_codex" ] && [ "$got_codex" != "$want" ] && ok=0
    if [ -n "$got_claude" ] && [ -n "$got_codex" ] && [ "$got_claude" != "$got_codex" ]; then
      ok=0  # 両系統ドリフト
    fi

    if [ "$ok" = 1 ]; then
      pass=$((pass + 1))
    else
      echo "FAIL $name: expected=$want claude=${got_claude:--} codex=${got_codex:--} input: $input"
      fail=$((fail + 1))
    fi
  done < "$cf"
done

# guard-codex-dir: jq 不在時に exit 2 (フェイルセーフ) となることを検証。
# 隔離した PATH で jq を見つけられない状態にして hook を直接実行する。
if [ -z "${HOOK_DIR:-}" ] && [ -f "$REPO_ROOT/agents/hooks/guard-codex-dir.sh" ]; then
  no_jq_bin="$WORKDIR/no-jq-bin"
  mkdir -p "$no_jq_bin"
  echo "==> guard-codex-dir (jq missing fail-safe)"
  jq_missing_rc=0
  printf '%s' '{"tool_input":{"file_path":".codex/config.toml"}}' \
    | (cd "$WORKDIR" && PATH="$no_jq_bin:/usr/bin:/bin" bash "$REPO_ROOT/agents/hooks/guard-codex-dir.sh" >/dev/null 2>&1) \
    || jq_missing_rc=$?
  if [ "$jq_missing_rc" = "2" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL guard-codex-dir jq-missing fail-safe: expected exit 2, got $jq_missing_rc"
    fail=$((fail + 1))
  fi
fi

# guard-sandbox-exclusions: jq 不在時に exit 2 (フェイルセーフ) となることを検証。
# 判定を持たないまま許可に倒れる経路が無いことの pin (issue #267)。
#
# 入力は **jq がある場合に allow (exit 0) になるもの**を使う。block 入力だと
# jq の有無に関わらず 2 が返るので、jq を実際に外せていなくてもテストが通ってしまう
# (codex-review qa-fixture が実証)。PATH も /usr/bin /bin を含めず、
# 実行に要る最小限だけを空ディレクトリに symlink して jq を確実に外す。
if [ -z "${HOOK_DIR:-}" ] && [ -f "$REPO_ROOT/claude/hooks/guard-sandbox-exclusions.sh" ]; then
  no_jq_bin="$WORKDIR/no-jq-bin"
  mkdir -p "$no_jq_bin"
  # hook が要る実行ファイルだけを symlink した PATH を組む。/usr/bin /bin を
  # 足すと jq がそこにある環境で外し損ねるため、この dir 単独で使う。
  excl_jq_bin_ok=1
  for b in bash cat awk tr grep; do
    b_path=$(command -v "$b" 2>/dev/null) || b_path=""
    if [ -n "$b_path" ]; then
      ln -sf "$b_path" "$no_jq_bin/$b"
    else
      excl_jq_bin_ok=0
    fi
  done
  echo "==> guard-sandbox-exclusions (jq missing fail-safe)"
  # 制御群: jq がある状態でこの入力が allow になることを先に確かめる
  excl_ctrl_rc=0
  printf '%s' '{"tool_input":{"command":"ls -la"}}' \
    | (cd "$WORKDIR" && HOME="$FAKE_HOME" \
        CLAUDE_GUARD_MANAGED_SETTINGS="$BASEDIR/no-managed-settings.json" \
        bash "$REPO_ROOT/claude/hooks/guard-sandbox-exclusions.sh" >/dev/null 2>&1) \
    || excl_ctrl_rc=$?
  if [ "$excl_ctrl_rc" = "0" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL guard-sandbox-exclusions jq-missing control: expected exit 0 with jq, got $excl_ctrl_rc"
    fail=$((fail + 1))
  fi
  excl_jq_rc=0
  excl_jq_err=$(printf '%s' '{"tool_input":{"command":"ls -la"}}' \
    | (cd "$WORKDIR" && HOME="$FAKE_HOME" \
        CLAUDE_GUARD_MANAGED_SETTINGS="$BASEDIR/no-managed-settings.json" \
        PATH="$no_jq_bin" \
        bash "$REPO_ROOT/claude/hooks/guard-sandbox-exclusions.sh" 2>&1 >/dev/null)) \
    || excl_jq_rc=$?
  case "$excl_jq_err" in
    *'jq 未インストール'*) excl_jq_msg_ok=1 ;;
    *) excl_jq_msg_ok=0 ;;
  esac
  if [ "$excl_jq_bin_ok" = "0" ]; then
    echo "SKIP guard-sandbox-exclusions jq-missing fail-safe: 必要な実行ファイルを解決できない"
  elif [ "$excl_jq_rc" = "2" ] && [ "$excl_jq_msg_ok" = "1" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL guard-sandbox-exclusions jq-missing fail-safe: expected exit 2 + jq 未インストール メッセージ, got rc=$excl_jq_rc msg=$excl_jq_err"
    fail=$((fail + 1))
  fi
fi

echo "----"
echo "hook tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
