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
#   `{{HOMEDIRLINK}}` / `{{CWDDIRLINK}}` は「保護対象ディレクトリ自体を指す、名前に
#   トークンを含まない symlink」(それぞれ home 配下プロジェクト / cwd 配下) に置換する。
#   `{{DOTDOTLINK}}` は「home 外に置かれ、home 配下プロジェクトのサブディレクトリを
#   指す symlink」(`/../` を後ろに付ける形の検証用)、`{{LEAFLINK}}` は「保護対象内の
#   ファイルを指す、末尾要素そのものの symlink」に置換する。
#   `{{RELLEAFLINK}}` は同じ形で target が相対パスのもの、`{{CHAINLEAFLINK}}` は
#   相対 → 絶対の 2 段 chain。
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
#   病的入力セクション (issue #314) だけは追加で timeout(1) / gtimeout / perl の
#   いずれか 1 つを使う。3 つとも解決できない環境ではそのセクションを SKIP する。
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

# {{HOMEDIRLINK}} / {{CWDDIRLINK}}: **名前にトークンを含まない** symlink が
# 保護対象ディレクトリ自体を指す状況。パス文字列に手掛かりが出ないため、
# normalize_path の gate 付き解決では発火せず素通りする形 (leaf が config.toml の
# ときだけ {{SYMHOME}} 側の gate が拾っていた)。file 編集 tool 経路が無条件解決に
# なっていることを pin する。
HOME_DIR_LINK="$FAKE_HOME/other-project/plainlink"
mkdir -p "$FAKE_HOME/other-project/.codex"
ln -sfn "$FAKE_HOME/other-project/.codex" "$HOME_DIR_LINK"

CWD_DIR_LINK="$WORKDIR/plainlink"
mkdir -p "$WORKDIR/.codex"
ln -sfn "$WORKDIR/.codex" "$CWD_DIR_LINK"

# {{DOTDOTLINK}}: home 外に置いた symlink が「隔離 HOME 配下プロジェクトのサブ
# ディレクトリ」を指す。`{{DOTDOTLINK}}/../.codex/x` は OS 解決だと保護対象に
# 着地するが、`..` を字句で畳むと home 外のパスに見える。
DOTDOT_LINK="$BASEDIR/dotdotlink"
mkdir -p "$FAKE_HOME/other-project/sub"
ln -sfn "$FAKE_HOME/other-project/sub" "$DOTDOT_LINK"
# `..` を字句で畳んだ側のパス ($BASEDIR/.codex) も**実在させる**。ここが無いと
# 字句解決した cd が失敗し、bash が元パスへフォールバックして物理解決と同じ結果に
# なるため、`cd -P` の有無を測れない (mutation で全 pass する形になる)。
mkdir -p "$BASEDIR/.codex"

# {{LEAFLINK}}: **末尾要素そのもの**が symlink で、保護対象内のファイルを指す。
# 祖先だけを解決する形だと判定は素通りするのに write は保護対象内へ着地する。
LEAF_LINK="$FAKE_HOME/other-project/notes.txt"
: >"$FAKE_HOME/other-project/.codex/config.toml"
ln -sfn "$FAKE_HOME/other-project/.codex/config.toml" "$LEAF_LINK"

# {{RELLEAFLINK}}: 末尾 symlink の target が **相対パス**。readlink の相対分岐
# (link の親ディレクトリ基準で解決する側) は絶対 target のケースでは通らない。
REL_LEAF_LINK="$FAKE_HOME/other-project/rel-notes.txt"
ln -sfn ".codex/config.toml" "$REL_LEAF_LINK"

# {{CHAINLEAFLINK}}: 相対 → 絶対の 2 段 symlink chain。1 段しか辿らない実装
# (while を if にする類の退行) を検出する。
ln -sfn "$FAKE_HOME/other-project/.codex/config.toml" "$FAKE_HOME/other-project/hop2.txt"
CHAIN_LEAF_LINK="$FAKE_HOME/other-project/hop1.txt"
ln -sfn "hop2.txt" "$CHAIN_LEAF_LINK"

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

# 病的入力セクション (issue #314) 用のタイムアウトラッパー。macOS には timeout(1) が
# 無いので 3 段で検出し、どれも解決できなければ空のまま = セクションごと SKIP する。
# perl 版が `alarm` + `exec` なのは、alarm タイマーが exec を跨いで生き残るため
# — ラッパープロセスが残らず、子の exit code もそのまま返る。
# 「この OS には perl がある」と決め打たずに実行時検出するのは、CI ランナーの
# pre-install 内容をこの repo から実測できないため (断定を書かない側に倒す)。
PATHO_TIMEOUT=10
TIMEOUT_CMD=()
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD=(timeout "$PATHO_TIMEOUT")
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD=(gtimeout "$PATHO_TIMEOUT")
elif command -v perl >/dev/null 2>&1; then
  TIMEOUT_CMD=(perl -e 'alarm shift; exec @ARGV' "$PATHO_TIMEOUT")
fi

run_hook() {
  # $1=hook path, $2=input (raw stdin content)。exit code を echo する (0/2 以外もそのまま)
  # $3 が非空なら $TIMEOUT_CMD を前置して $PATHO_TIMEOUT 秒で打ち切る (呼び出し側が
  # 先に TIMEOUT_CMD の非空を確かめる)。打ち切り時の exit code は timeout(1) /
  # gtimeout が 124、perl が 142 (128+SIGALRM)。
  # HOOK_TEST_STRIP_JQ=1 のとき PATH から jq を除外して hook を実行 (fail-safe 検証)。
  # HOME は隔離 HOME に差し替える (実ユーザー環境からの分離)。
  # CLAUDE_GUARD_MANAGED_SETTINGS は guard-sandbox-exclusions.sh が読む managed
  # settings のパス。HOME / cwd の隔離ではホスト側の
  # /Library/Application Support/ClaudeCode/ を外せないため、存在しないパスを
  # 明示して MDM 管理端末でも CI と同じ結果になるようにする。
  # 打ち切り経路を別関数に切らずここへ足すのは、隔離の 3 点セット (cd / HOME /
  # CLAUDE_GUARD_MANAGED_SETTINGS) を 2 箇所で持つとドリフトするため。
  local rc=0
  local nosettings="$BASEDIR/no-managed-settings.json"
  if [ -n "${3:-}" ]; then
    # サブシェルの外側にもう一段 2>/dev/null を掛けるのは、SIGALRM で打ち切られたとき
    # `Alarm clock: 14 ...` の job 通知を出すのが hook ではなく**このサブシェル自身**で、
    # 内側の 2>&1 では落とせないため。
    printf '%s' "$2" | (cd "$WORKDIR" && HOME="$FAKE_HOME" CLAUDE_GUARD_MANAGED_SETTINGS="$nosettings" "${TIMEOUT_CMD[@]}" bash "$1" >/dev/null 2>&1) 2>/dev/null || rc=$?
  elif [ "${HOOK_TEST_STRIP_JQ:-0}" = "1" ]; then
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
  s=${s//\{\{HOMEDIRLINK\}\}/$HOME_DIR_LINK}
  s=${s//\{\{CWDDIRLINK\}\}/$CWD_DIR_LINK}
  s=${s//\{\{DOTDOTLINK\}\}/$DOTDOT_LINK}
  s=${s//\{\{LEAFLINK\}\}/$LEAF_LINK}
  s=${s//\{\{RELLEAFLINK\}\}/$REL_LEAF_LINK}
  s=${s//\{\{CHAINLEAFLINK\}\}/$CHAIN_LEAF_LINK}
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

  # 候補抽出 (extract_edit_paths_nul) の途中段が落ちたときの fail-safe。
  # プロセス置換の終了ステータスは while に伝播しないため、抽出が失敗すると
  # 「候補 0 件」= allow と区別が付かない。awk だけを PATH から外して
  # 「終端レコードが来なければ block」の経路を発火させる (jq 不在は手前の
  # command -v jq で止まるので、この経路を測れるのは awk 側だけ)。
  echo "==> guard-codex-dir (抽出失敗 fail-safe)"
  no_awk_bin="$WORKDIR/no-awk-bin"
  mkdir -p "$no_awk_bin"
  for _real in /usr/bin/jq /usr/local/bin/jq /opt/homebrew/bin/jq; do
    [ -x "$_real" ] && ln -sfn "$_real" "$no_awk_bin/jq" && break
  done
  if [ ! -e "$no_awk_bin/jq" ]; then
    _jq_path=$(command -v jq 2>/dev/null || true)
    [ -n "$_jq_path" ] && ln -sfn "$_jq_path" "$no_awk_bin/jq"
  fi
  # awk 以外はすべて張る (bash 自身も PATH 解決されるので必要)。
  for _tool in bash cat sed tr readlink; do
    for _dir in /usr/bin /bin; do
      [ -x "$_dir/$_tool" ] && ln -sfn "$_dir/$_tool" "$no_awk_bin/$_tool" && break
    done
  done
  awk_missing_rc=0
  printf '%s' '{"tool_input":{"file_path":"README.md"}}' \
    | (cd "$WORKDIR" && HOME="$FAKE_HOME" PATH="$no_awk_bin" \
        bash "$REPO_ROOT/agents/hooks/guard-codex-dir.sh" >/dev/null 2>&1) \
    || awk_missing_rc=$?
  if [ "$awk_missing_rc" = "2" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL guard-codex-dir 抽出失敗 fail-safe: expected exit 2, got $awk_missing_rc"
    fail=$((fail + 1))
  fi

  # $HOME 自体が symlink の環境。home_forms の 2 要素目 (pwd -P 解決後の $HOME) が
  # 使われる経路は、runner の通常 HOME (実ディレクトリ) では一度も発火しない。
  # symlink 表記と実体表記の**両方**で block されることを見る。
  echo "==> guard-codex-dir (HOME が symlink)"
  home_symlink="$BASEDIR/home-as-link"
  ln -sfn "$FAKE_HOME" "$home_symlink"
  for _spelling in "$home_symlink" "$FAKE_HOME"; do
    home_link_rc=0
    printf '{"tool_input":{"file_path":"%s/.codex/config.toml"}}' "$_spelling" \
      | (cd "$WORKDIR" && HOME="$home_symlink" \
          bash "$REPO_ROOT/agents/hooks/guard-codex-dir.sh" >/dev/null 2>&1) \
      || home_link_rc=$?
    if [ "$home_link_rc" = "2" ]; then
      pass=$((pass + 1))
    else
      echo "FAIL guard-codex-dir HOME-symlink ($_spelling): expected exit 2, got $home_link_rc"
      fail=$((fail + 1))
    fi
  done

  # apply_patch ヘッダーから剥がす空白集合 (hook の ws[]) と、その全要素を行末位置で
  # 測るケース群 (jsonl の「ヘッダー行末」) が一致することを見る。hook 側のコメントは
  # 1:1 対応を宣言しているが、宣言だけだと集合に足したときテスト側の追加を忘れても
  # 緑のまま通り、足した要素だけ無検査になる (shell.md の「全部入り fixture は対象が
  # 増えた瞬間に黙って古くなる」)。
  #
  # 突き合わせるのは**件数ではなくバイト列そのもの**。件数だけだと、要素を 1 つ足す
  # と同時に既存コードポイントの重複ケースを足した形が釣り合ってしまい、足した要素
  # だけ無検査で通る (codex-review qa-fixture 指摘)。ケース名の `U+XXXX` ラベルを
  # 数える形も、ラベルは実際に入っているバイトのプロキシでしかないので使わない。
  echo "==> guard-codex-dir (空白集合とケースのバイト一致)"
  # ws[] の octal エスケープを実バイトへ戻して hex 化する。`printf "$esc"` は
  # フォーマット文字列側の `\ddd` を octal として解釈する経路 (%b ではないのは、
  # ws[] の表記が awk のリテラルと同じ `\302\240` 形式で、`\0` 前置が無いため)。
  ws_bytes=$(grep -o 'ws\[++nws\] = "[^"]*"' "$REPO_ROOT/agents/hooks/guard-codex-dir.sh" \
    | sed -e 's/^.*= "//' -e 's/"$//' \
    | while IFS= read -r _esc; do
        # shellcheck disable=SC2059  # octal エスケープの解釈がここでの目的
        printf "$_esc" | od -An -tx1 | tr -d ' \n'
        echo
      done | LC_ALL=C sort)
  # ケース側は「ヘッダー行に config.toml が現れたあとの残り」= 付けた空白そのもの。
  # block ケースだけを数える。同じ「ヘッダー行末」でも、剥がしすぎを検出する
  # allow 側のラチェット (U+200B) は**集合の外**の文字を測るケースなので混ぜない。
  case_bytes=$(grep '"block: apply_patch ヘッダー行末 ' "$REPO_ROOT/tests/hooks/guard-codex-dir.cases.jsonl" \
    | while IFS= read -r _line; do
        printf '%s' "$_line" | jq -r '.tool_input.patch' \
          | awk '/Update File:/ { i = index($0, "config.toml"); if (i) printf "%s", substr($0, i + 11) }' \
          | od -An -tx1 | tr -d ' \n'
        echo
      done | LC_ALL=C sort)
  ws_n=$(printf '%s\n' "$ws_bytes" | grep -c . || true)
  case_uniq_n=$(printf '%s\n' "$case_bytes" | LC_ALL=C sort -u | grep -c . || true)
  if [ "$ws_n" -gt 0 ] && [ "$ws_bytes" = "$case_bytes" ] && [ "$ws_n" = "$case_uniq_n" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL guard-codex-dir ws/case parity: ws[]=$ws_n 件 / ケース(重複除去後)=$case_uniq_n 件、バイト集合の一致=$([ "$ws_bytes" = "$case_bytes" ] && echo yes || echo no)"
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

# block-dangerous-commands: 病的入力が短時間で判定を返すことの pin (issue #314)。
# `_check_glob_seg` の派生候補ループは、内側の検査が文字列全体を再走査する形にすると
# 入力長に対して超線形に伸びる。PR #315 で実際に踏み、1816 字で 82.07s (main は 0.45s)
# になったが、そのとき機能テストは 309 passed / 0 failed で退行を示さなかった
# — exit code しか見ていないため、遅いだけのケースは pass になる。
# この hook は Bash tool 呼び出しごとに毎回走るので、遅さはそのままシェルの摩擦になる。
# 全ケースに一律のタイムアウトを掛けないのは、事故が起きた経路だけを pin する方針
# (claude/rules/shell.md「毎回走るゲートに suffix ごとに検査を回す形を足したら…」) に
# 合わせるため。
# `a=/` を 2400 回 (7215 字) 並べるのは、**事故当時の 1816 字では足りないため**。
# 同じ commit (95b690d) で `_matches_codex` に足した先頭 1 文字の fast path が
# 効くので、`_check_components` の切り詰めだけを外した退行は 1816 字だと 2.92s に
# しかならず 10s 閾値を下回る。2026-08-10 に切り詰めのみを外して実測した対比
# (修正済み / 退行版): 915 字 0.10s / 0.68s、1816 字 0.12s / 2.92s、
# 3615 字 0.18s / 15.19s、7215 字 0.36s / 91.0s。7215 字なら閾値 10s から
# 正常側に 28 倍・退行側に 9 倍離れており、ランナーの性能差では跨げない。
patho_check() {
  # $1=hook path, $2=input, $3=FAIL 時に出すラベル。allow (exit 0) で返れば pass。
  local rc
  rc=$(run_hook "$1" "$2" timed)
  if [ "$rc" = "0" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $3: expected exit 0, got $rc (124/142 は ${PATHO_TIMEOUT}s タイムアウト)"
    fail=$((fail + 1))
  fi
}

patho_hooks=()
if [ -z "${HOOK_DIR:-}" ]; then
  for _h in "$REPO_ROOT/claude/hooks/block-dangerous-commands.sh" "$REPO_ROOT/codex/hooks/block-dangerous-commands.sh"; do
    if [ -f "$_h" ]; then
      patho_hooks+=("$_h")
    fi
  done
fi
if [ "${#patho_hooks[@]}" -gt 0 ]; then
  echo "==> block-dangerous-commands (病的入力の実行時間)"
  if [ "${#TIMEOUT_CMD[@]}" -eq 0 ]; then
    echo "SKIP block-dangerous-commands 病的入力: timeout / gtimeout / perl のいずれも解決できない"
  else
    patho_ctrl=$(jq -nc '{tool_input:{command:"curl -o out a=/b $X"}}')
    patho_seg=$(printf 'a=/%.0s' {1..2400})
    patho_cmd="curl -o out $patho_seg \$X"
    patho_input=$(jq -nc --arg c "$patho_cmd" '{tool_input:{command:$c}}')
    for _h in "${patho_hooks[@]}"; do
      _label="${_h#"$REPO_ROOT/"}"
      # 制御群を先に見るのは、タイムアウト機構が壊れて常に打ち切る状態でも本体は
      # FAIL するため。同型の短い入力まで落ちていれば「退行を検出した」ではない。
      patho_check "$_h" "$patho_ctrl" "$_label 病的入力の制御群 (落ちるのは計測機構側の異常)"
      patho_check "$_h" "$patho_input" "$_label 病的入力 ${#patho_cmd} 字 (落ちるのは超線形化の退行)"
    done
  fi
fi

echo "----"
echo "hook tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
