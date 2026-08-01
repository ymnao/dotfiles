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
  local matcher="$1" tool="$2" harness="$3" exact_re part
  [ -z "$matcher" ] && return 0        # 空 matcher は match-all
  [ "$matcher" = "*" ] && return 0     # `*` も match-all
  # 完全一致に落ちる文字集合は harness で違う (Claude は `,` と `-` も含む)。
  if [ "$harness" = "claude" ]; then
    exact_re='^[a-zA-Z0-9_|, -]+$'
  else
    exact_re='^[a-zA-Z0-9_|]+$'
  fi
  if [[ "$matcher" =~ $exact_re ]]; then
    # `|` (claude は `,` も) で分割して完全一致。部分一致はしない。
    local IFS='|'
    [ "$harness" = "claude" ] && IFS='|,'
    for part in $matcher; do
      # 前後の空白は実装側で trim される
      part="${part#"${part%%[![:space:]]*}"}"
      part="${part%"${part##*[![:space:]]}"}"
      [ "$part" = "$tool" ] && return 0
    done
    return 1
  fi
  # それ以外は regex として評価 (アンカー無し = 部分一致)
  [[ "$tool" =~ $matcher ]]
}

# 1. claude/settings.json: guard-codex-dir が Edit/Write/MultiEdit/NotebookEdit/Bash を全部拾えるか
CLAUDE_SETTINGS="$REPO_ROOT/claude/settings.json"
for tool in Edit Write MultiEdit NotebookEdit Bash; do
  hit=0
  # 各 PreToolUse エントリの matcher を取り出し、tool 名にマッチする group で guard-codex-dir が命令されているか
  while IFS= read -r entry; do
    matcher=$(printf '%s' "$entry" | jq -r '.matcher')
    if [ -n "$matcher" ] && matcher_matches "$matcher" "$tool" claude; then
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
    if [ -n "$matcher" ] && matcher_matches "$matcher" "$tool" codex; then
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
