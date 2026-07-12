#!/usr/bin/env bash
set -uo pipefail

# run-integrity-check.sh 自体のシナリオテスト。
# 偽の dotfiles と偽の HOME を組み立て、正常構成で PASS・改ざん各種で FAIL に
# なることを検証する (検知器が壊れて常に OK を返す退行の防止)。
#
# 依存: bash 3.2+ / jq / git

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CHECKER="${CHECKER_PATH:-$SCRIPT_DIR/run-integrity-check.sh}"

if [ ! -f "$CHECKER" ]; then
  echo "ERROR: checker not found: $CHECKER" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }

BASE="$(mktemp -d "${TMPDIR:-/tmp}/integrity-tests.XXXXXX")"
cleanup() { [ -n "${BASE:-}" ] && rm -rf "$BASE"; }
trap cleanup EXIT

pass=0
fail=0

# 偽 dotfiles を作る
DF="$BASE/dotfiles"
mkdir -p "$DF/agents" "$DF/claude/skills" "$DF/claude/hooks" "$DF/claude/agents" \
         "$DF/claude/rules" "$DF/codex/hooks" "$DF/codex/skills/pr"
printf 'agents\n' >"$DF/agents/AGENTS.md"
printf '{}\n' >"$DF/claude/settings.json"
printf 'sl\n' >"$DF/claude/statusline.sh"
printf 'codex agents\n' >"$DF/codex/AGENTS.md"
printf '{}\n' >"$DF/codex/hooks.json"
printf 'model = "x"\n' >"$DF/codex/config.toml"

# 正常な偽 HOME を作る。$1=HOME パス
make_good_home() {
  local h="$1"
  mkdir -p "$h/.claude" "$h/.codex/skills"
  ln -s "$DF/agents/AGENTS.md"      "$h/.claude/CLAUDE.md"
  ln -s "$DF/claude/settings.json"  "$h/.claude/settings.json"
  ln -s "$DF/claude/skills"         "$h/.claude/skills"
  ln -s "$DF/claude/hooks"          "$h/.claude/hooks"
  ln -s "$DF/claude/agents"         "$h/.claude/agents"
  ln -s "$DF/claude/rules"          "$h/.claude/rules"
  ln -s "$DF/claude/statusline.sh"  "$h/.claude/statusline.sh"
  ln -s "$DF/codex/AGENTS.md"       "$h/.codex/AGENTS.md"
  ln -s "$DF/codex/hooks.json"      "$h/.codex/hooks.json"
  ln -s "$DF/codex/hooks"           "$h/.codex/hooks"
  ln -s "$DF/codex/skills/pr"       "$h/.codex/skills/pr"
  # マージ方式の config.toml (base + 保護セクション)
  { cat "$DF/codex/config.toml"; printf '\n[projects."/x"]\ntrust_level = "trusted"\n'; } \
    >"$h/.codex/config.toml"
}

run_checker() {
  # $1=HOME。exit code を echo
  local rc=0
  INTEGRITY_HOME="$1" INTEGRITY_DOTFILES="$DF" bash "$CHECKER" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

check() {
  # $1=名前, $2=期待 exit, $3=実際
  if [ "$3" = "$2" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $1: expected=$2 got=$3"
    fail=$((fail + 1))
  fi
}

# 1. 正常構成 → OK
H="$BASE/home-ok"; make_good_home "$H"
check "all-good" 0 "$(run_checker "$H")"

# 2. .claude が無い環境 → SKIP (exit 0)
H="$BASE/home-empty"; mkdir -p "$H"
check "no-claude-skip" 0 "$(run_checker "$H")"

# 3. symlink が実体ファイルにすり替わっている → FAIL
H="$BASE/home-replaced"; make_good_home "$H"
rm "$H/.claude/settings.json"
printf '{"hacked":true}\n' >"$H/.claude/settings.json"
check "replaced-file" 1 "$(run_checker "$H")"

# 4. symlink 先が別の場所を指している → FAIL
H="$BASE/home-rewired"; make_good_home "$H"
rm "$H/.claude/hooks"
mkdir -p "$BASE/evil-hooks"
ln -s "$BASE/evil-hooks" "$H/.claude/hooks"
check "rewired-link" 1 "$(run_checker "$H")"

# 5. symlink が消えている → FAIL
H="$BASE/home-missing"; make_good_home "$H"
rm "$H/.claude/rules"
check "missing-link" 1 "$(run_checker "$H")"

# 6. codex config.toml の base 部分が書き換えられている → FAIL
H="$BASE/home-toml"; make_good_home "$H"
{ printf 'model = "evil"\n'; printf '\n[projects."/x"]\ntrust_level = "trusted"\n'; } \
  >"$H/.codex/config.toml"
check "toml-base-tampered" 1 "$(run_checker "$H")"

# 7. codex config.toml が symlink 化されている → FAIL
H="$BASE/home-toml-link"; make_good_home "$H"
rm "$H/.codex/config.toml"
ln -s "$DF/codex/config.toml" "$H/.codex/config.toml"
check "toml-symlinked" 1 "$(run_checker "$H")"

# 8. ~/.claude.json に未許可の MCP 定義 → FAIL
H="$BASE/home-mcp"; make_good_home "$H"
printf '{"mcpServers":{"evil-proxy":{"command":"nc"}}}\n' >"$H/.claude.json"
check "unknown-mcp-global" 1 "$(run_checker "$H")"

# 9. プロジェクト単位の MCP 注入も検出 → FAIL
H="$BASE/home-mcp-proj"; make_good_home "$H"
printf '{"projects":{"/x":{"mcpServers":{"backdoor":{"command":"nc"}}}}}\n' >"$H/.claude.json"
check "unknown-mcp-project" 1 "$(run_checker "$H")"

# 10. MCP 定義なしの ~/.claude.json → OK
H="$BASE/home-mcp-ok"; make_good_home "$H"
printf '{"projects":{"/x":{"allowedTools":[]}}}\n' >"$H/.claude.json"
check "no-mcp-ok" 0 "$(run_checker "$H")"

echo "----"
echo "integrity selftest: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
