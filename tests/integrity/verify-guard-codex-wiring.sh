#!/usr/bin/env bash
#
# guard-codex-dir hook の配線が壊れていないことを構造的に検証する。
#
# 検証項目:
#   1. claude/settings.json の PreToolUse 内で guard-codex-dir.sh が
#      Edit / Write / MultiEdit / NotebookEdit / Bash の全ツール名にマッチする matcher に紐付いている
#   2. codex/hooks.json の PreToolUse でも同 hook が Bash と apply_patch/Edit/Write にマッチする
#   3. claude/hooks/guard-codex-dir.sh と codex/hooks/guard-codex-dir.sh が
#      同一の agents/hooks/guard-codex-dir.sh に解決される (drift 防止)
#
# 依存: bash 3.2+ / jq / readlink

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"

pass=0
fail=0

check() {
  # $1=condition (0=OK / non-zero=fail), $2=description
  if [ "$1" = "0" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL: $2"
    fail=$((fail + 1))
  fi
}

matcher_matches() {
  # $1=matcher, $2=ツール名, $3=harness (claude|codex)
  #
  # **両 harness とも matcher は「正規表現一本槍」ではない**。match-all / 完全一致 /
  # regex の 3 分岐で評価され、英数字と区切り文字だけの matcher は **完全一致**側に
  # 落ちる (実測根拠は docs/ai-operations.md §10)。
  #
  # 以前ここは `[[ "$2" =~ $1 ]]` の部分一致近似で、コメントにも「Perl 相当の
  # 正規表現」と書いていたが、その前提が誤りだった。部分一致で検査すると
  # `dit|rite|ultiEdit|otebookEdit` のような綴り違いが対象ツール全件に一致して
  # 緑のまま通るのに、実機では guard-codex-dir.sh が一度も発火しない。
  # ここは ~/.codex を守る**遮断層**の配線検査なので、受理側の口を実装に合わせる。
  local matcher="$1" tool="$2" harness="$3" exact_re sep part
  # 空 matcher / `*` は match-all
  if [ -z "$matcher" ] || [ "$matcher" = "*" ]; then
    return 0
  fi
  # 完全一致に落ちる文字集合と分割文字は harness で違う (Claude は `,` と `-` も含む)。
  if [ "$harness" = "claude" ]; then
    exact_re='^[a-zA-Z0-9_|, -]+$'
    sep='|,'
  else
    exact_re='^[a-zA-Z0-9_|]+$'
    sep='|'
  fi
  if [[ "$matcher" =~ $exact_re ]]; then
    # 分割して完全一致。部分一致はしない。
    local IFS="$sep"
    for part in $matcher; do
      # 前後の空白は実装側で trim される
      part="${part#"${part%%[![:space:]]*}"}"
      part="${part%"${part##*[![:space:]]}"}"
      if [ "$part" = "$tool" ]; then
        return 0
      fi
    done
    return 1
  fi
  # それ以外は regex として評価 (アンカー無し = 部分一致)
  [[ "$tool" =~ $matcher ]]
}

# --- 0. matcher_matches 自体の回帰テスト ---
# この関数は「実 harness がどう突合するか」の写し。実配置の matcher は
# たまたま完全一致でも部分一致でも通るため、**実配置を検査する項目 1-3 だけでは
# 実装を部分一致近似に戻しても全部緑のまま**になる。実際それがこの関数の
# 誤った前提が長く生き延びた理由なので、守りたい挙動を直接測る
# (claude/rules/shell.md「pin を足したら守りたい状態を作る mutation で確かめる」)。
assert_matcher() {
  # $1=harness, $2=matcher, $3=tool, $4=期待値 (yes|no)
  local got=no
  if matcher_matches "$2" "$3" "$1"; then
    got=yes
  fi
  check "$([ "$got" = "$4" ] && echo 0 || echo 1)" \
    "matcher_matches: harness=$1 matcher=[$2] tool=$3 は $4 のはず (got: $got)"
}

# match-all の 2 形 (空 / `*`) — 呼び出し側で空を弾くと実 harness と判定がずれる
assert_matcher claude ''  Edit yes
assert_matcher claude '*' Edit yes
assert_matcher codex  ''  Bash yes
assert_matcher codex  '*' Bash yes
# 完全一致: 実配置の形
assert_matcher claude 'Edit|Write|MultiEdit|NotebookEdit' Edit         yes
assert_matcher claude 'Edit|Write|MultiEdit|NotebookEdit' NotebookEdit yes
assert_matcher claude 'Edit|Write|MultiEdit|NotebookEdit' Bash         no
# 完全一致: 綴り違いを取り逃がさないこと (部分一致近似への退行を落とす回帰ケース)
assert_matcher claude 'dit|rite|ultiEdit|otebookEdit' Edit         no
assert_matcher claude 'dit|rite|ultiEdit|otebookEdit' NotebookEdit no
assert_matcher codex  'ash'                           Bash         no
# 完全一致: Claude だけカンマ区切りと前後空白の trim を受ける
assert_matcher claude 'Edit, Write' Write yes
# 同じ文字列は codex では charset を外れて regex 側に落ち、一致しない
assert_matcher codex  'Edit, Write' Write no
# regex fallback: アンカー付きは境界どおりに効く
assert_matcher claude '^(Edit|Write)$' Edit         yes
assert_matcher claude '^(Edit|Write)$' NotebookEdit no
assert_matcher codex  '^Bash$'         Bash         yes
assert_matcher codex  '^(apply_patch|Edit|Write)$' apply_patch yes

# 1. claude/settings.json: guard-codex-dir が Edit/Write/MultiEdit/NotebookEdit/Bash を全部拾えるか
CLAUDE_SETTINGS="$REPO_ROOT/claude/settings.json"
for tool in Edit Write MultiEdit NotebookEdit Bash; do
  hit=0
  # 各 PreToolUse エントリの matcher を取り出し、tool 名にマッチする group で guard-codex-dir が命令されているか
  while IFS= read -r entry; do
    matcher=$(printf '%s' "$entry" | jq -r '.matcher')
    # 空 matcher を呼び出し側で弾かない — 実 harness では match-all なので、
    # 弾くと「実際は全ツールを守れている配線」を未配線と誤判定する。
    # 判定は matcher_matches に一本化する (上の回帰テストが担保)。
    if matcher_matches "$matcher" "$tool" claude; then
      cmds=$(printf '%s' "$entry" | jq -r '.hooks[].command')
      if printf '%s' "$cmds" | grep -q 'guard-codex-dir.sh'; then
        hit=1
        break
      fi
    fi
  done < <(jq -c '.hooks.PreToolUse[]' "$CLAUDE_SETTINGS")
  check "$([ "$hit" = 1 ] && echo 0 || echo 1)" "claude/settings.json: $tool 用の matcher に guard-codex-dir が紐付いていない"
done

# 2. codex/hooks.json: Bash と apply_patch/Edit/Write に guard-codex-dir が紐付いているか
CODEX_HOOKS="$REPO_ROOT/codex/hooks.json"
for tool in Bash apply_patch Edit Write; do
  hit=0
  while IFS= read -r entry; do
    matcher=$(printf '%s' "$entry" | jq -r '.matcher')
    if matcher_matches "$matcher" "$tool" codex; then
      cmds=$(printf '%s' "$entry" | jq -r '.hooks[].command')
      if printf '%s' "$cmds" | grep -q 'guard-codex-dir.sh'; then
        hit=1
        break
      fi
    fi
  done < <(jq -c '.hooks.PreToolUse[]' "$CODEX_HOOKS")
  check "$([ "$hit" = 1 ] && echo 0 || echo 1)" "codex/hooks.json: $tool 用の matcher に guard-codex-dir が紐付いていない"
done

# 3. symlink 解決: claude/hooks と codex/hooks の guard-codex-dir が agents/hooks/ の同一実体に解決される
canonical="$(cd "$REPO_ROOT/agents/hooks" && pwd -P)/guard-codex-dir.sh"
for side in claude codex; do
  hook_path="$REPO_ROOT/$side/hooks/guard-codex-dir.sh"
  # symlink を辿った実体パスを取得 (BSD/GNU 両対応: python があれば realpath 相当、なければ readlink で近似)
  actual=""
  if command -v python3 >/dev/null 2>&1; then
    actual=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$hook_path")
  elif command -v realpath >/dev/null 2>&1; then
    actual=$(realpath "$hook_path")
  else
    # 手動で symlink を 1 段辿る
    link_target=$(readlink "$hook_path" || printf '%s' "$hook_path")
    case "$link_target" in
      /*) actual=$link_target ;;
      *) actual="$(cd "$(dirname "$hook_path")" && cd "$(dirname "$link_target")" && pwd -P)/$(basename "$link_target")" ;;
    esac
  fi
  if [ "$actual" = "$canonical" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL: $side/hooks/guard-codex-dir.sh が agents/hooks/ の実体に解決されない ($actual != $canonical)"
    fail=$((fail + 1))
  fi
done

echo "guard-codex wiring: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
