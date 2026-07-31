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
#
# 旧実装は「既知書式にマッチしたパスだけを照合し、抽出結果が完全に空のときだけ
# fail する」形だった。これは取りこぼしの落ち先が pass なので、`${HOME}` 表記・
# `~` 表記・拡張子なし・別インタプリタ等で 1 件配線が増えると、照合対象から
# 静かに外れて assert 自体が無効化される (issue #213)。
#
# そこで **配線 command を 1 件残らず分類し、分類できないものは違反にする** 形に
# 変える。分類は command 文字列の *全体* に対して行う:
#   1. 単一起動形 (`<インタプリタ> "<パス 1 個>"`) — パスを正規化して
#      WATCHED_PATHS と前方一致照合し、外れていれば違反
#   2. 単一起動形でない command — 下の NON_REPO_EXPECTED と全文一致すれば pass
#   3. それ以外すべて — 違反
#
# **部分一致で断片だけ拾う形にしないのが要点**。断片抽出だと、同じ command 内の
# *それ以外の* 参照が検査されない (例: `bash "$HOME/.claude/hooks/a.sh" &&
# bash /path/to/repo/scripts/b.sh` の後半が丸ごと素通りする)。command 全体の形を
# pin すれば、想定外の形は必ず未分類として落ちる。
#
# 取りこぼしの落ち先が pass から fail に変わる。誤検知 (正当な新書式で落ちる) は
# 起こりうるが、その場合は classify_wired_commands の受理パターンを拡張すればよい。
#
# **この検査でも捕まらないと分かっているもの** (「観測していない = 起きない」と
# 書かないため、既知の穴として明記する):
#   - repo 内ファイルを指す配線が **すべて** 消えた場合。jq は「hooks が空」でも
#     「ファイルが空」でも exit 0 かつ空出力を返すため、分類対象がゼロになっても
#     違反は出ない。これは下の MIN_REPO_COMMANDS_* の下限 assert で別に受ける
#   - NON_REPO_EXPECTED に安易に追記して通す運用。構造では防げないので、
#     リスト側のコメントで追加時の確認事項を明示するに留めている
#
# 対象に含めないもの (意図的):
#   - codex/config.toml の notify — 値は repo 外の絶対パス (host バイナリ) を
#     指しており repo 内ファイルを参照しない。含めると「repo 外パスの正当性判定」
#     という別の分類問題を持ち込むことになる。ファイル自体は WATCHED_PATHS に
#     載っているので改変検知はされる。将来 notify が repo 内ファイルを指すよう
#     変わった場合、この検査では捕まらない
#   - .claude/stop-gate.conf の中身 (`make gate`) — 同上。間接実行の連鎖まで
#     広げない方針は hooks-integrity-warn.sh の WATCHED_PATHS コメントに準ずる
#   - .claude/settings.json — WATCHED_PATHS には載っているが配線の抽出元には
#     していない。2026-07-31 時点の中身は `$schema` / `permissions` / `sandbox` の
#     3 キーで `.hooks` を持たない (実測)。ただしこれは現在の中身の観測であって
#     形式上の保証ではない (project settings は hooks を持てる)。ここに hook を
#     足すときは抽出元にも追加すること

# 単一起動形にマッチしない command の全文 pin。
# 形式上は allowlist だが、ここに無い command が現れたら違反になるので drift は
# 必ず顕在化する (通すにはこのリストの意図的な更新 = レビューが要る)。
# **追加する前に、その command が repo 内ファイルを一切参照しないことを確認する**
# (引数に repo 内パスを足す改変を素通しさせないため、第 1 トークンではなく全文で pin する)。
# なお出所ファイルと重複は保持しない (3 経路の出力を連結して sort -u するため)。
# 同じ command を別ファイル・別イベントへ移す種類の drift は検出対象外。
NON_REPO_EXPECTED=$(cat <<'EOF'
afplay /System/Library/Sounds/Funk.aiff
osascript -e 'display notification "タスクが完了しました" with title "Claude Code" sound name "Glass"'
EOF
)

# jq を 1 経路実行する。失敗したら違反行を stdout に出して非 0 を返す
# (旧実装は 2>/dev/null で jq エラーごと握りつぶしていた)。
run_jq_extract() {
  # $1=経路の説明, $2=jq 式, $3=対象ファイル
  local out
  if ! out=$(jq -r "$2" "$3" 2>&1); then
    printf 'jq 抽出に失敗 (%s): %s\n' "$1" "$out"
    return 1
  fi
  printf '%s\n' "$out"
}

# 複数行になりうる値を「1 行 1 違反」で出す。`printf 'prefix: %s\n' "$multiline"` だと
# prefix が 1 行目にしか付かず、2 行目以降が prefix 無しの生 command 行として出て
# しまう (ケース 15 の needle 照合がその行に当たると vacuous pass になる)。
print_violations() {
  # $1=prefix, $2=違反の値 (改行区切り。空なら何も出さない)
  local prefix="$1" line
  [ -n "$2" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '%s: %s\n' "$prefix" "$line"
  done <<<"$2"
}

# repo 相対パス $1 が監視対象一覧 $2 (改行区切り) のいずれかに前方一致するか。
path_is_watched() {
  # $1=repo 相対パス, $2=--list-watched の出力
  local rel="$1" w
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    case "$rel" in
      "$w" | "$w"/*) return 0 ;;
    esac
  done <<<"$2"
  return 1
}

# 配線 command を全件分類し、**違反を 1 行 1 件で stdout に出す**。違反が無ければ無出力。
# exit code ではなく一覧を返すのは、ケース 15 の negative 検証 (違反が出ることを
# 期待する側) をケース 14 と同じ関数で回すため。
classify_wired_commands() {
  # $1=claude/settings.json 相当のパス, $2=codex/hooks.json 相当のパス
  local claude_json="$1" codex_json="$2"
  local watched commands chunk cmd argpath rel i
  local descs queries files
  local nonrepo_actual expected_sorted extra missing

  watched=$(bash "$HOOK" --list-watched) || {
    printf '%s\n' "--list-watched の取得に失敗しました"
    return 0
  }

  # 抽出経路は 3 つ。同じブロックを書き写す形にすると、写し漏れでエラー
  # ハンドリングの抜けた経路が生まれる。握りつぶしの復活はこの変更がまさに
  # 直そうとしている問題そのものなので、経路を配列で持って 1 箇所で回す。
  descs=(
    "${claude_json} の hooks"
    "${claude_json} の statusLine"
    "${codex_json} の hooks"
  )
  queries=(
    '.hooks | to_entries[] | .value[].hooks[].command'
    '.statusLine.command // empty'
    '.hooks | to_entries[] | .value[].hooks[].command'
  )
  files=("$claude_json" "$claude_json" "$codex_json")
  commands=""
  for i in "${!descs[@]}"; do
    if ! chunk=$(run_jq_extract "${descs[$i]}" "${queries[$i]}" "${files[$i]}"); then
      printf '%s\n' "$chunk"
      return 0
    fi
    commands="${commands}
${chunk}"
  done

  nonrepo_actual=""
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    # command 全体が「インタプリタ + パス 1 個」の単一起動形かを見る。
    # 部分一致で断片を拾う形にしない理由は上のブロックコメントを参照。
    argpath=$(
      printf '%s\n' "$cmd" |
        sed -nE 's#^(bash|sh|zsh|python3|node) "?([^"]+)"?$#\2#p'
    )
    if [ -z "$argpath" ]; then
      # 単一起動形でない → 全文 pin と突合する側に回す。
      nonrepo_actual="${nonrepo_actual}${cmd}
"
      continue
    fi
    # 正規化を試み、**置換されなかったこと**で「home 配下 dotfiles を指していない」を
    # 判定する。判定用のパターンを別に持つと 2 つが drift するので、正規化の
    # 1 本だけを真実にする (`$HOME` / `${HOME}` / `~` の 3 表記を受ける)。
    rel=$(sed -E 's#^(\$\{?HOME\}?|~)/\.([a-z]+)/#\2/#' <<<"$argpath")
    if [ "$rel" = "$argpath" ]; then
      # 単一起動形だが home 配下 dotfiles を指していない。repo 内ファイルを
      # 別表記で実行している可能性があるので、安全側に倒して違反にする。
      printf '想定外の実行パス (home 配下 dotfiles を指していません): %s\n' "$cmd"
      continue
    fi
    # `..` を含むパスは監視対象の外へ抜けられるのに、前方一致では
    # 「監視対象内」と判定される (実測: claude/hooks/../../scripts/link.sh は
    # claude/hooks/* に一致するが、実体は WATCHED_PATHS 外の scripts/)。
    # 正規化して救うのではなく、素直に違反にする。
    case "/${rel}/" in
      */../*)
        printf '相対参照を含む実行パス (前方一致照合が破れます): %s\n' "$rel"
        continue
        ;;
    esac
    path_is_watched "$rel" "$watched" ||
      printf '監視対象外 (配線されているが WATCHED_PATHS に無い): %s\n' "$rel"
  done <<<"$commands"

  # 単一起動形でない command は全文 pin と双方向で突合する。増えた分だけでなく
  # 減った分も違反にするのは、pin 側が実態から離れて空リスト同然になる drift を
  # 防ぐため。`grep -Fxv` の `-x` (行全体一致) は必須 — 外すと空パターン行が
  # 全行に一致して静かに全通しになる (実測で確認)。
  # LC_ALL=C はファイル冒頭で export 済み (日本語を含む行をバイト順で安定させる)。
  nonrepo_actual=$(printf '%s' "$nonrepo_actual" | grep -v '^$' | sort -u)
  expected_sorted=$(printf '%s\n' "$NON_REPO_EXPECTED" | grep -v '^$' | sort -u)
  if [ -n "$nonrepo_actual" ]; then
    extra=$(printf '%s\n' "$nonrepo_actual" | grep -Fxv -f <(printf '%s\n' "$expected_sorted"))
    print_violations '未分類 command (NON_REPO_EXPECTED に無い)' "$extra"
  fi
  if [ -n "$expected_sorted" ]; then
    missing=$(printf '%s\n' "$expected_sorted" | grep -Fxv -f <(printf '%s\n' "$nonrepo_actual"))
    print_violations 'NON_REPO_EXPECTED に載っているが配線に無い command' "$missing"
  fi
}

violations=$(classify_wired_commands \
  "$REPO_ROOT/claude/settings.json" "$REPO_ROOT/codex/hooks.json")
check_empty "$violations" "配線 command が全件分類され、監視対象から漏れていないこと"

# 分類器は「違反が無いこと」しか言わないので、**分類対象が消えた**ケースを別に受ける。
# jq は hooks が空でもファイルが空でも exit 0 かつ空出力を返すため、配線が丸ごと
# 消滅しても分類器は無違反 = clean のまま通る (実測で確認)。
# 下限は claude/rules/shell.md の規約どおり **守る対象から導出せず独立した定数**で
# 持つ (配列長等から計算すると、対象が減ったときに下限も一緒に下がって無効化される)。
# 値は 2026-07-31 時点の実測: claude/settings.json = hooks 9 件 + statusLine 1 件、
# codex/hooks.json = 7 件。配線を意図的に減らすときはここも更新する。
MIN_REPO_COMMANDS_CLAUDE=10
MIN_REPO_COMMANDS_CODEX=7

count_repo_ref_commands() {
  # $1=対象 JSON, $2 以降=jq 式 (複数可)。home 配下 dotfiles を指す command を数える。
  # jq 失敗時は 0 件になり下限 assert が落ちる (fail-closed) ので握りつぶしてよい。
  local file="$1" q total=0 n
  shift
  for q in "$@"; do
    n=$(jq -r "$q" "$file" 2>/dev/null | grep -cE '(\$\{?HOME\}?|~)/\.(claude|codex)/' || true)
    total=$((total + n))
  done
  printf '%s\n' "$total"
}

n_claude=$(count_repo_ref_commands "$REPO_ROOT/claude/settings.json" \
  '.hooks | to_entries[] | .value[].hooks[].command' '.statusLine.command // empty')
check_cmd "claude/settings.json の repo 参照 command が ${MIN_REPO_COMMANDS_CLAUDE} 件以上あること (got ${n_claude})" \
  [ "$n_claude" -ge "$MIN_REPO_COMMANDS_CLAUDE" ]
n_codex=$(count_repo_ref_commands "$REPO_ROOT/codex/hooks.json" \
  '.hooks | to_entries[] | .value[].hooks[].command')
check_cmd "codex/hooks.json の repo 参照 command が ${MIN_REPO_COMMANDS_CODEX} 件以上あること (got ${n_codex})" \
  [ "$n_codex" -ge "$MIN_REPO_COMMANDS_CODEX" ]

# --- 15. 上記の網羅性検査そのものが drift を検出できることの回帰検査 ---
# ケース 14 は「今の配線が clean である」ことしか言わない。旧実装が silent pass
# だった以上、**検査側が本当に落ちるか** を別に確かめないと同じ穴が再発する。
#
# fixture は実 settings.json に jq で hook を 1 件だけ足したコピー。
# mutation を適用したら「実際に 1 件だけ増えた」ことを確認してから判定する
# (claude/rules/shell.md の mutation 規約。この repo は設計コメントが厚く、
# 置換が空振りして偽陰性の結論になった前歴が 2 回ある)。
CASE15_DIR="$WORK/case15"
mkdir -p "$CASE15_DIR"

assert_case15() {
  # $1=ケース名, $2=追加する command, $3=expect-clean|expect-violation,
  # $4=違反一覧に現れるべき文字列 (expect-violation のときのみ参照)
  local name="$1" cmd="$2" mode="$3" needle="${4:-}"
  local out before after added has_cmd violations
  out="$CASE15_DIR/${name}.json"
  jq --arg cmd "$cmd" \
    '.hooks.SessionStart += [{"hooks":[{"type":"command","timeout":10,"command":$cmd}]}]' \
    "$REPO_ROOT/claude/settings.json" > "$out" || {
    check "1" "${name}: fixture の生成に失敗"
    return
  }

  # mutation の実効確認 (件数 +1 かつ狙った command 文字列が実在すること)。
  before=$(jq -r '.hooks | to_entries[] | .value[].hooks[].command' \
    "$REPO_ROOT/claude/settings.json" | grep -c . || true)
  after=$(jq -r '.hooks | to_entries[] | .value[].hooks[].command' "$out" | grep -c . || true)
  added=$((after - before))
  check_cmd "${name}: mutation で配線 command が 1 件だけ増えること (got ${added})" \
    [ "$added" = "1" ]
  has_cmd=$(jq -r --arg cmd "$cmd" \
    '[.hooks | to_entries[] | .value[].hooks[].command | select(. == $cmd)] | length' "$out")
  check_cmd "${name}: 追加した command 文字列が fixture に実在すること (got ${has_cmd})" \
    [ "$has_cmd" = "1" ]

  violations=$(classify_wired_commands "$out" "$REPO_ROOT/codex/hooks.json")
  case "$mode" in
    expect-clean)
      check_empty "$violations" "${name}: 違反として報告されないこと"
      ;;
    expect-violation)
      # needle は **違反行の全文** で照合する (grep -qxF)。部分一致にすると、
      # 分類が別の理由で落ちて出た行に needle がたまたま含まれるだけで pass する
      # (実測: 断片検出を never-match に変えた mutant でも、生 command 行を含む
      # 別種の違反が出るため部分一致では通ってしまった)。
      # 空 needle のガードも要る — `grep -qF -- ""` は空の違反一覧にも一致する。
      if [ -z "$needle" ]; then
        check "1" "${name}: expect-violation には needle (違反行の全文) が必須"
        return
      fi
      # パイプではなく herestring を使う。`printf | grep -q` は grep が一致で
      # 即終了するため、入力がパイプバッファを超えると printf が write error を
      # 返し、pipefail 下で「一致しているのに非 0」になる (実測: rc=1)。
      grep -qxF -- "$needle" <<<"$violations"
      check "$?" "${name}: 違反として報告されること (needle=${needle}, got: ${violations})"
      ;;
  esac
}

# 15a: 書式が違う (${HOME} ブレース表記) が監視対象内 → 通ること。
#      旧実装はこの形を抽出できず、照合対象から静かに落としていた。
assert_case15 "case15a-brace-watched" \
  'bash "${HOME}/.claude/hooks/post-format.sh"' expect-clean
# 15b: 監視対象外のディレクトリに配線された → 落ちること (受け入れ条件の本体)。
assert_case15 "case15b-unwatched-path" \
  'bash "$HOME/.claude/notwatched/x.sh"' expect-violation \
  '監視対象外 (配線されているが WATCHED_PATHS に無い): claude/notwatched/x.sh'
# 15c: 単一起動形でなく pin にも無い command → 落ちること。
assert_case15 "case15c-unknown-nonrepo" \
  'say done' expect-violation \
  '未分類 command (NON_REPO_EXPECTED に無い): say done'
# 15d: home 配下 dotfiles を指さない単一起動形 → 落ちること。
assert_case15 "case15d-not-dotfiles-path" \
  'bash "$HOME/.claude"' expect-violation \
  '想定外の実行パス (home 配下 dotfiles を指していません): bash "$HOME/.claude"'
# 15e: **書式違い かつ 監視対象外** → 落ちること。issue #213 が指摘した穴そのもの。
#      15b は `$HOME` 表記なので旧実装でも捕まえられた形で、旧実装が silent pass
#      していたのはこの組み合わせ (抽出できない → 照合対象から外れる → 素通り)。
assert_case15 "case15e-brace-unwatched" \
  'bash "${HOME}/.claude/notwatched/y.sh"' expect-violation \
  '監視対象外 (配線されているが WATCHED_PATHS に無い): claude/notwatched/y.sh'
# 15f: `..` で監視対象の外へ抜けるパス → 落ちること。前方一致照合だけでは
#      claude/hooks/* に一致して「監視対象内」と誤判定される形 (実測で再現済み)。
assert_case15 "case15f-parent-traversal" \
  'bash "${HOME}/.claude/hooks/../../scripts/link.sh"' expect-violation \
  '相対参照を含む実行パス (前方一致照合が破れます): claude/hooks/../../scripts/link.sh'
# 15g: 監視対象内の参照に **別の実行を連結** した形 → 落ちること。
#      断片抽出方式だと前半だけが照合され後半が丸ごと素通りする経路で、
#      command 全体の形を pin する設計に切り替えた理由そのもの。
assert_case15 "case15g-extra-invocation" \
  'bash "$HOME/.claude/hooks/post-format.sh" && bash /tmp/evil.sh' expect-violation \
  '未分類 command (NON_REPO_EXPECTED に無い): bash "$HOME/.claude/hooks/post-format.sh" && bash /tmp/evil.sh'

echo "hooks-integrity: ${pass} passed, ${fail} failed"
[ "$fail" = 0 ] || exit 1
