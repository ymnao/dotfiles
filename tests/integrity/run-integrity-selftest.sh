#!/usr/bin/env bash
set -uo pipefail

# tests/integrity/ 配下の検知器 script 群の selftest。
# 偽の dotfiles / 偽の HOME / 偽の settings.json を組み立て、正常構成で PASS・
# 改ざん各種で FAIL になることを検証する (検知器が壊れて常に OK を返す退行の防止)。
# 対象: run-integrity-check.sh, verify-settings-codex-domains.sh
# (issue #189 で 3 項目分、issue #190 で denyWrite 項目分を追加)。
# verify-guard-codex-wiring.sh の selftest は未実装 (別 issue で対応予定)。
#
# 依存: bash 3.2+ / jq / git

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CHECKER="${CHECKER_PATH:-$SCRIPT_DIR/run-integrity-check.sh}"
SETTINGS_VERIFIER="${SETTINGS_VERIFIER_PATH:-$SCRIPT_DIR/verify-settings-codex-domains.sh}"
TRUST_CHECKER="${TRUST_CHECKER_PATH:-$SCRIPT_DIR/verify-codex-hook-trust.sh}"

if [ ! -f "$CHECKER" ]; then
  echo "ERROR: checker not found: $CHECKER" >&2
  exit 1
fi
if [ ! -f "$SETTINGS_VERIFIER" ]; then
  echo "ERROR: settings verifier not found: $SETTINGS_VERIFIER" >&2
  exit 1
fi
if [ ! -f "$TRUST_CHECKER" ]; then
  echo "ERROR: trust checker not found: $TRUST_CHECKER" >&2
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

# ---- verify-settings-codex-domains.sh の selftest (issue #189) ----
# 検知器が壊れて常に PASS を返す退行を防ぐ。base fixture は 4 項目を全て
# 含み、tamper 版はそれぞれ 1 項目を欠落/破壊して FAIL 期待。
run_settings_verifier() {
  # $1=settings.json パス。exit code を echo
  local rc=0
  INTEGRITY_SETTINGS="$1" bash "$SETTINGS_VERIFIER" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

make_good_settings() {
  # $1=出力パス。verify-settings-codex-domains.sh の 4 項目を全て満たす最小 JSON
  jq -n '{
    sandbox: {
      network: { allowedDomains: ["chatgpt.com", "auth.openai.com", "example.com"] },
      filesystem: {
        allowWrite: ["~/.codex", "/tmp"],
        denyWrite: ["~/.zshrc", "~/.codex/config.toml"]
      }
    }
  }' >"$1"
}

SF="$BASE/settings-ok.json"; make_good_settings "$SF"
check "settings-baseline-ok" 0 "$(run_settings_verifier "$SF")"

# fixture 1: allowedDomains から chatgpt.com を除外 → FAIL
SF="$BASE/settings-no-chatgpt.json"; make_good_settings "$SF"
jq '.sandbox.network.allowedDomains -= ["chatgpt.com"]' "$SF" >"$SF.tmp" && mv "$SF.tmp" "$SF"
check "settings-missing-chatgpt" 1 "$(run_settings_verifier "$SF")"

# fixture 2: allowedDomains から auth.openai.com を除外 → FAIL
SF="$BASE/settings-no-authopenai.json"; make_good_settings "$SF"
jq '.sandbox.network.allowedDomains -= ["auth.openai.com"]' "$SF" >"$SF.tmp" && mv "$SF.tmp" "$SF"
check "settings-missing-auth-openai" 1 "$(run_settings_verifier "$SF")"

# fixture 3: allowWrite から ~/.codex を除外 → FAIL
SF="$BASE/settings-no-codex-write.json"; make_good_settings "$SF"
jq '.sandbox.filesystem.allowWrite -= ["~/.codex"]' "$SF" >"$SF.tmp" && mv "$SF.tmp" "$SF"
check "settings-missing-codex-write" 1 "$(run_settings_verifier "$SF")"

# fixture 4: allowedDomains を配列でなく単一文字列に化かす → FAIL
# (round 1 で fix した type-punning loophole の regression 防止)
SF="$BASE/settings-domains-string.json"; make_good_settings "$SF"
jq '.sandbox.network.allowedDomains = "chatgpt.com,auth.openai.com"' "$SF" >"$SF.tmp" && mv "$SF.tmp" "$SF"
check "settings-domains-string-not-array" 1 "$(run_settings_verifier "$SF")"

# fixture 5: denyWrite から ~/.codex/config.toml を除外 → FAIL
# (issue #190: allowWrite の ~/.codex 全体に対して config.toml だけ deny する
#  設計が消えると notify 経由の sandbox escape 経路が復活する)
SF="$BASE/settings-no-config-deny.json"; make_good_settings "$SF"
jq '.sandbox.filesystem.denyWrite -= ["~/.codex/config.toml"]' "$SF" >"$SF.tmp" && mv "$SF.tmp" "$SF"
check "settings-missing-config-toml-deny" 1 "$(run_settings_verifier "$SF")"

# fixture 6: denyWrite キー自体を消す → FAIL
# (`-=` による要素除去とは別経路。denyWrite ブロックごと削除された drift で
#  any(.[]?; ...) が null 入力で false を返すことを確認する)
SF="$BASE/settings-no-deny-key.json"; make_good_settings "$SF"
jq 'del(.sandbox.filesystem.denyWrite)' "$SF" >"$SF.tmp" && mv "$SF.tmp" "$SF"
check "settings-denywrite-key-absent" 1 "$(run_settings_verifier "$SF")"

# fixture 7: denyWrite を配列でなく単一文字列に化かす → FAIL
# (fixture 4 と同じ type-punning drift を deny 側でも押さえる。現行の check_contains は
#  any(.[]?; . == $v) なので文字列入力では `.[]?` が empty になり false へ倒れる。
#  かつて index() 実装だった頃は substring 一致で false PASS しえたため、実装を
#  index() 系に戻す「簡略化」への回帰検出も兼ねる)
SF="$BASE/settings-deny-string.json"; make_good_settings "$SF"
jq '.sandbox.filesystem.denyWrite = "~/.zshrc,~/.codex/config.toml"' "$SF" >"$SF.tmp" && mv "$SF.tmp" "$SF"
check "settings-deny-string-not-array" 1 "$(run_settings_verifier "$SF")"

# ---- verify-codex-hook-trust.sh の selftest (issue #239) ----
# この検査は warn-only (全経路 exit 0) なので、exit code だけを見る run_checker
# では「常に OK を返す退行」を一切検出できない。stdout を assert する経路を
# 別に用意し、「警告が出るべきときに出る」と「出るべきでないときに出ない」の
# 両方を固定する (片方だけだと vacuous pass する)。

# 偽 HOME に hooks 定義入りの hooks.json と、承認記録つき config.toml を作る。
# $1=HOME パス、$2 以降=承認済みにする entry ("session_start:0:0" 形式)。
# hooks.json は 3 entry (pre_tool_use:0:0 / 0:1 と session_start:0:0) を持つ。
make_trust_home() {
  local h="$1"; shift
  mkdir -p "$h/.codex"
  jq -n '{
    hooks: {
      PreToolUse: [ { matcher: "^Bash$", hooks: [
        { type: "command", command: "bash a.sh" },
        { type: "command", command: "bash b.sh" }
      ] } ],
      SessionStart: [ { matcher: "startup", hooks: [
        { type: "command", command: "bash c.sh" }
      ] } ]
    }
  }' >"$h/.codex/hooks.json"
  : >"$h/.codex/config.toml"
  local e
  for e in "$@"; do
    printf '[hooks.state."%s/.codex/hooks.json:%s"]\ntrusted_hash = "sha256:deadbeef"\n\n' \
      "$h" "$e" >>"$h/.codex/config.toml"
  done
}

run_trust_checker() {
  # $1=HOME。stdout を返す (exit code は check_trust_exit で別に見る)
  INTEGRITY_HOME="$1" bash "$TRUST_CHECKER" 2>/dev/null
}

check_trust_exit() {
  # $1=名前, $2=HOME。warn-only の契約 (run-gate.sh は set -e) を固定する
  local rc=0
  INTEGRITY_HOME="$2" bash "$TRUST_CHECKER" >/dev/null 2>&1 || rc=$?
  check "$1" 0 "$rc"
}

check_stdout_has() {
  # $1=名前, $2=出力, $3=含まれるべき文字列
  if printf '%s\n' "$2" | LC_ALL=C grep -Fq "$3"; then
    pass=$((pass + 1))
  else
    echo "FAIL $1: 出力に '$3' が含まれない"
    fail=$((fail + 1))
  fi
}

check_stdout_lacks() {
  # $1=名前, $2=出力, $3=含まれてはいけない文字列
  if printf '%s\n' "$2" | LC_ALL=C grep -Fq "$3"; then
    echo "FAIL $1: 出力に '$3' が含まれてはいけない"
    fail=$((fail + 1))
  else
    pass=$((pass + 1))
  fi
}

# trust-1. 3 entry すべて承認済み → OK のみ、WARN なし
H="$BASE/trust-all"; make_trust_home "$H" "pre_tool_use:0:0" "pre_tool_use:0:1" "session_start:0:0"
out=$(run_trust_checker "$H")
check_stdout_has   "trust-all-approved-ok"    "$out" "codex-hook-trust: OK"
check_stdout_lacks "trust-all-approved-nowarn" "$out" "WARN"
check_trust_exit   "trust-all-approved-exit0" "$H"

# trust-2. session_start だけ未承認 → その entry の WARN が出て、承認済みの
# entry の WARN は出ない (「全部 WARN する」退行と「何も WARN しない」退行の両方を殺す)
H="$BASE/trust-partial"; make_trust_home "$H" "pre_tool_use:0:0" "pre_tool_use:0:1"
out=$(run_trust_checker "$H")
check_stdout_has   "trust-partial-warns-missing" "$out" "未承認の codex hook entry: session_start:0:0"
check_stdout_lacks "trust-partial-quiet-approved" "$out" "未承認の codex hook entry: pre_tool_use:0:0"
check_stdout_lacks "trust-partial-not-ok"        "$out" "codex-hook-trust: OK"
check_trust_exit   "trust-partial-exit0"         "$H"

# trust-3. config.toml が無い (= 承認記録ゼロ) → 3 entry 全部 WARN。
# 「配線済みなのに承認記録が 1 件も無い」はまさに検知したい状態なので skip ではなく警告
H="$BASE/trust-noconfig"; make_trust_home "$H"
rm -f "$H/.codex/config.toml"
out=$(run_trust_checker "$H")
warn_count=$(printf '%s\n' "$out" | LC_ALL=C grep -c "未承認の codex hook entry:" | tr -d ' ')
check "trust-noconfig-warn-count" 3 "$warn_count"
check_trust_exit "trust-noconfig-exit0" "$H"

# trust-4. 承認記録はあるが **別 HOME のパス** で登録されている → WARN。
# 照合キーに hooks.json の絶対パスが効いていることの mutation テスト。
# パス部分を落とす簡略化 (":session_start:0:0" の suffix 一致等) をすると、
# 他ホストの承認記録を自ホストの承認と取り違えるが、それをここで固定する。
H="$BASE/trust-otherpath"; make_trust_home "$H" "pre_tool_use:0:0" "pre_tool_use:0:1" "session_start:0:0"
LC_ALL=C sed -e "s|$H/.codex/hooks.json|/other/home/.codex/hooks.json|g" \
  "$H/.codex/config.toml" >"$H/.codex/config.toml.tmp"
mv "$H/.codex/config.toml.tmp" "$H/.codex/config.toml"
out=$(run_trust_checker "$H")
check_stdout_has "trust-otherpath-warns" "$out" "未承認の codex hook entry: session_start:0:0"
check_stdout_lacks "trust-otherpath-not-ok" "$out" "codex-hook-trust: OK"

# trust-5. ~/.codex が無い (codex 未セットアップ機) → SKIP
H="$BASE/trust-nocodex"; mkdir -p "$H"
out=$(run_trust_checker "$H")
check_stdout_has   "trust-nocodex-skip"   "$out" "codex-hook-trust: SKIP"
check_stdout_lacks "trust-nocodex-nowarn" "$out" "WARN"

# trust-6. hooks.json が無い → SKIP
H="$BASE/trust-nohooksjson"; mkdir -p "$H/.codex"
out=$(run_trust_checker "$H")
check_stdout_has   "trust-nohooksjson-skip"   "$out" "codex-hook-trust: SKIP"
check_stdout_lacks "trust-nohooksjson-nowarn" "$out" "WARN"

# trust-7. hooks 定義が空の hooks.json → entry 0 件なので OK (警告を出さない)。
# `.hooks // {}` の fallback が効いていることの固定
H="$BASE/trust-emptyhooks"; mkdir -p "$H/.codex"
printf '{}\n' >"$H/.codex/hooks.json"
: >"$H/.codex/config.toml"
out=$(run_trust_checker "$H")
check_stdout_has   "trust-emptyhooks-ok"    "$out" "codex-hook-trust: OK"
check_stdout_lacks "trust-emptyhooks-nowarn" "$out" "WARN"

echo "----"
echo "integrity selftest: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
