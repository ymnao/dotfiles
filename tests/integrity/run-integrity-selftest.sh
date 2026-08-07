#!/usr/bin/env bash
set -uo pipefail

# tests/integrity/ 配下の検知器 script 群の selftest。
# 偽の dotfiles / 偽の HOME / 偽の settings.json を組み立て、正常構成で PASS・
# 改ざん各種で FAIL になることを検証する (検知器が壊れて常に OK を返す退行の防止)。
# 対象: run-integrity-check.sh, verify-settings-codex-domains.sh,
# verify-codex-hook-trust.sh, verify-sandbox-exclusion-guard.sh
# (issue #189 で 3 項目分、issue #190 で denyWrite 項目分、issue #239 で
#  codex hook の承認状態検査分、issue #214 で trusted_hash の値検証分を追加)。
# verify-guard-codex-wiring.sh の selftest は未実装 (別 issue で対応予定)。
#
# 依存: bash 3.2+ / jq / git / sha256sum または shasum
# (最後のものは verify-codex-hook-trust.sh の hash 計算が要求する。どちらも
#  無いホストでは検査器が SKIP を返し、trust-* の stdout assert が全部落ちる)

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
# 検知器が壊れて常に PASS を返す退行を防ぐ。base fixture は 5 項目を全て
# 含み、tamper 版はそれぞれ 1 項目を欠落/破壊して FAIL 期待。
run_settings_verifier() {
  # $1=settings.json パス。exit code を echo
  local rc=0
  INTEGRITY_SETTINGS="$1" bash "$SETTINGS_VERIFIER" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

make_good_settings() {
  # $1=出力パス。verify-settings-codex-domains.sh の 5 項目を全て満たす最小 JSON
  jq -n '{
    sandbox: {
      network: { allowedDomains: ["chatgpt.com", "auth.openai.com", "example.com"] },
      filesystem: {
        allowWrite: ["~/.codex", "/tmp"],
        denyWrite: ["~/.zshrc", "~/.codex/config.toml", "~/development/**/.codex/**"]
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

# fixture 5b: denyWrite から ~/development/**/.codex/** を除外 → FAIL
# (issue #289: プロジェクト配下の .codex/ を Bash 経路で止める一次防御が消える)
SF="$BASE/settings-no-project-codex-deny.json"; make_good_settings "$SF"
jq '.sandbox.filesystem.denyWrite -= ["~/development/**/.codex/**"]' "$SF" >"$SF.tmp" && mv "$SF.tmp" "$SF"
check "settings-missing-project-codex-deny" 1 "$(run_settings_verifier "$SF")"

# fixture 5c: 同エントリを「JSON としては妥当だが sandbox では効かない表記」に
# 化かす → FAIL。実測 (2026-08-08) で、先頭が `**/` の非絶対エントリは警告なしに
# 無視される。存在検査だけの pin だと通ってしまう形なので全文一致で塞いでいる。
SF="$BASE/settings-project-codex-relative.json"; make_good_settings "$SF"
jq '.sandbox.filesystem.denyWrite |= map(if . == "~/development/**/.codex/**" then "**/.codex/**" else . end)' \
  "$SF" >"$SF.tmp" && mv "$SF.tmp" "$SF"
check "settings-project-codex-non-absolute" 1 "$(run_settings_verifier "$SF")"

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
# hooks.json は 5 entry (pre_tool_use:0:0 / 0:1 / 1:0、session_start:0:0、stop:0:0)。
# **PreToolUse に group を 2 つ置くのは意図的** — 1 event 1 group だけの
# fixture では、キーの <group> 軸を落とす退行 (jq の \($g) を 0 に固定する等) が
# 全 pass のまま生き残る。実 codex/hooks.json は PreToolUse に 2 group
# (^Bash$ と ^(apply_patch|Edit|Write)$) を持つので、これは仮想の穴ではない。
#
# hash 検証 (issue #214) のために、fixture は payload 仕様の分岐を全て踏む:
#   - pre_tool_use:0:0 — timeout / statusMessage なし (既定値 600 と省略の経路)
#   - pre_tool_use:0:1 — timeout / statusMessage あり (明示値の経路。
#     statusMessage は非 ASCII — payload は UTF-8 生出力で \u エスケープしない)
#   - stop:0:0         — matcher が空文字列 (**キーごと省略**される経路)
# 後ろ 2 つは 0.145.0 の再実測で解けなかった当の分岐なので、ここで固定する。
make_trust_home() {
  local h="$1"; shift
  mkdir -p "$h/.codex"
  jq -n '{
    hooks: {
      PreToolUse: [
        { matcher: "^Bash$", hooks: [
          { type: "command", command: "bash a.sh" },
          { type: "command", command: "bash b.sh", timeout: 7, statusMessage: "実行中..." }
        ] },
        { matcher: "^(apply_patch|Edit|Write)$", hooks: [
          { type: "command", command: "bash d.sh" }
        ] }
      ],
      SessionStart: [ { matcher: "startup", hooks: [
        { type: "command", command: "bash c.sh" }
      ] } ],
      Stop: [ { matcher: "", hooks: [
        { type: "command", command: "bash e.sh" }
      ] } ]
    }
  }' >"$h/.codex/hooks.json"
  : >"$h/.codex/config.toml"
  local e
  for e in "$@"; do
    write_trust_entry "$h/.codex/config.toml" "$h/.codex/hooks.json" "$e" \
      "$(trust_expected_hash "$e")"
  done
}

# 承認記録ブロック 1 件を追記する。**検査器が照合しているのは codex が書き出す
# basic string 書式ちょうど 1 つ**なので、その書式をケースごとに手書きすると
# 片方だけずれて「なぜか 1 ケースだけ通らない」形で出る。ここ 1 箇所に閉じ込める。
# $1=出力先 config.toml, $2=キーに埋める hooks.json のパス, $3=entry,
# $4=trusted_hash の値 (空文字なら **キー行だけ書いて trusted_hash 行を省く**)
write_trust_entry() {
  if [ -n "$4" ]; then
    printf '[hooks.state."%s:%s"]\ntrusted_hash = "%s"\n\n' "$2" "$3" "$4" >>"$1"
  else
    printf '[hooks.state."%s:%s"]\n\n' "$2" "$3" >>"$1"
  fi
}

# 上の fixture に対する期待 trusted_hash。**リテラル定数として持つ** —
# 検査器と同じコードで計算し直すと、payload 生成が壊れても期待値が一緒に
# ずれて全 pass する (「floor / guard を守る対象から導出しない」規約)。
# 値は codex-cli 0.146.0 の payload 仕様で 1 度計算したもの (issue #214)。
# 検査器と生成元が同じ jq 式である弱さは trust-hash-3 の mutation
# (hooks.json 側を書き換えると MISMATCH に転じる) が補う。
# 未知の entry 名には合致しない値を返す — テスト側の綴り間違いが
# 「承認済み扱いで素通り」ではなく MISMATCH として見えるようにするため。
trust_expected_hash() {
  case "$1" in
    pre_tool_use:0:0)  printf 'sha256:f76a4f1f84aab48e952fdd043a881d2cfcd1ffc543a772acf8eee08bffdd9df4' ;;
    pre_tool_use:0:1)  printf 'sha256:4f6297e026bbd885804bfa22f10dfb0ade7d100aa1498e9ee36460f837e43a1b' ;;
    pre_tool_use:1:0)  printf 'sha256:980c38e2945bab05e69c013327396d19f5b732f94c8734ba077bb678e143c6af' ;;
    session_start:0:0) printf 'sha256:08c52d1af6f5de3e1b98a5a4ca6d8bdbfadf683906ec433f614994d48635f038' ;;
    stop:0:0)          printf 'sha256:474176a8d69f3dd291b648fde2a27fbf4f46c94f4dd9f736f026efacefe7bf03' ;;
    *)                 printf 'sha256:unknown-entry-in-test-fixture' ;;
  esac
}

# 配列で持つ (空白区切り文字列 + unquoted 展開の word splitting は
# claude/rules/shell.md の「変数展開は常に quote する」に反する。
# `make test` の shellcheck は -S warning なので SC2086 では止まらない)
ALL_TRUST_ENTRIES=(
  "pre_tool_use:0:0" "pre_tool_use:0:1" "pre_tool_use:1:0"
  "session_start:0:0" "stop:0:0"
)

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

# trust-1. 5 entry すべて承認済み・hash 一致 → OK のみ、WARN なし。
# **payload 仕様の回帰はここで落ちる** — 期待値は独立した定数なので、
# matcher 空の省略・timeout 既定 600・キーのソート順・非 ASCII の生出力の
# どれが崩れても該当 entry が MISMATCH になる (fail-loud)
H="$BASE/trust-all"
make_trust_home "$H" "${ALL_TRUST_ENTRIES[@]}"
out=$(run_trust_checker "$H")
# entry 件数まで assert する — 「全部承認済み」と「検査対象が 0 件」が同じ OK で
# 出ると、この層の存在理由 (動いていないことが見えない) を 1 段上で再生産する
check_stdout_has   "trust-all-approved-ok"    "$out" "codex-hook-trust: OK (5 entry すべて承認済み・hash 一致)"
check_stdout_lacks "trust-all-approved-nowarn" "$out" "WARN"
check_trust_exit   "trust-all-approved-exit0" "$H"

# trust-1b. **HOME に末尾スラッシュが付いていても同じ結果**。連結が `//` になると
# codex が書いた正規化済みパスと prefix が一致せず全 entry が「未承認」に化ける。
# 同型の落とし穴は claude/rules/shell.md に規約化済み (issue #225)。
# 直前の trust-1 と同じ fixture を使い、**変える変数は末尾スラッシュだけ**
out=$(run_trust_checker "$H/")
check_stdout_has   "trust-trailing-slash-ok"     "$out" "codex-hook-trust: OK (5 entry すべて承認済み・hash 一致)"
check_stdout_lacks "trust-trailing-slash-nowarn" "$out" "WARN"

# trust-2. session_start だけ未承認 → その entry の WARN が出て、承認済みの
# entry の WARN は出ない (「全部 WARN する」退行と「何も WARN しない」退行の両方を殺す)
H="$BASE/trust-partial"
make_trust_home "$H" "pre_tool_use:0:0" "pre_tool_use:0:1" "pre_tool_use:1:0" "stop:0:0"
out=$(run_trust_checker "$H")
check_stdout_has   "trust-partial-warns-missing" "$out" "未承認の codex hook entry: session_start:0:0"
check_stdout_lacks "trust-partial-quiet-approved" "$out" "未承認の codex hook entry: pre_tool_use:0:0"
check_stdout_lacks "trust-partial-not-ok"        "$out" "codex-hook-trust: OK"
# 件数サマリ行の中身を pin する。この行は「件数で原因を断定しない」と決めた結果
# user が最初に読む行になったが、4 つのカウンタを総入れ替えした mutant が
# 全 pass していた (= 一度も測られていなかった)
check_stdout_has   "trust-partial-summary"       "$out" \
  "承認済み 4 / 未承認 1 / hash 不一致 0 / 読み取り不可 0 (対象 5 entry)"
# **ヒントの「出さない側」を固定する**。不一致が 0 件なのに不一致ヒントが出ると、
# 「再承認する前に再実測せよ」が平常状態で常時発火して意味を失う。
# 条件を `if true` に緩めた退行はこれが無いと全 pass で通る
check_stdout_lacks "trust-partial-no-mismatch-hint" "$out" "承認後に hooks.json を書き換えた"
check_trust_exit   "trust-partial-exit0"         "$H"

# trust-2b. **同一 event の 2 つ目の group だけ**が未承認 → その entry の WARN が出る。
# キーの <group> 軸が実際に測られていることの mutation テスト。group を落とす退行
# (jq の \($g) を 0 に固定する等) をすると 1:0 が承認済みの 0:0 に潰れて黙って通る。
# trust-1 / trust-2 だけではこの退行が全 pass のまま生き残っていた
H="$BASE/trust-group"
make_trust_home "$H" "pre_tool_use:0:0" "pre_tool_use:0:1" "session_start:0:0" "stop:0:0"
out=$(run_trust_checker "$H")
check_stdout_has   "trust-group-warns-second-group" "$out" "未承認の codex hook entry: pre_tool_use:1:0"
check_stdout_lacks "trust-group-quiet-first-group"  "$out" "未承認の codex hook entry: pre_tool_use:0:0"
check_trust_exit   "trust-group-exit0"              "$H"

# trust-3. config.toml が無い (= 承認記録ゼロ) → 5 entry 全部 WARN。
# 「配線済みなのに承認記録が 1 件も無い」はまさに検知したい状態なので skip ではなく警告
H="$BASE/trust-noconfig"; make_trust_home "$H"
rm -f "$H/.codex/config.toml"
out=$(run_trust_checker "$H")
warn_count=$(printf '%s\n' "$out" | LC_ALL=C grep -cF "未承認の codex hook entry:")
check "trust-noconfig-warn-count" 5 "$warn_count"
check_trust_exit "trust-noconfig-exit0" "$H"

# trust-4. 承認記録はあるが **別 HOME のパス** で登録されている → WARN。
# 照合キーに hooks.json の絶対パスが効いていることの mutation テスト。
# パス部分を落とす簡略化 (":session_start:0:0" の suffix 一致等) をすると、
# 他ホストの承認記録を自ホストの承認と取り違えるが、それをここで固定する。
H="$BASE/trust-otherpath"
make_trust_home "$H" "${ALL_TRUST_ENTRIES[@]}"
# パスを差し替えた config.toml を組み直す (sed で $H を BRE に埋めると、
# mktemp 由来のパスに含まれるメタ文字で壊れるため文字列連結で作る)。
# hash は正しい値を入れる — 「パスが違えば hash が合っていても未承認」を
# 固定するため (hash 一致を承認の代わりに使う退行を殺す)
: >"$H/.codex/config.toml"
for e in "${ALL_TRUST_ENTRIES[@]}"; do
  write_trust_entry "$H/.codex/config.toml" "/other/home/.codex/hooks.json" "$e" \
    "$(trust_expected_hash "$e")"
done
out=$(run_trust_checker "$H")
check_stdout_has "trust-otherpath-warns" "$out" "未承認の codex hook entry: session_start:0:0"
check_stdout_lacks "trust-otherpath-not-ok" "$out" "codex-hook-trust: OK"
check_trust_exit "trust-otherpath-exit0" "$H"

# trust-4b. 承認記録がコメント行としてだけ存在する → WARN。
# 照合が「ファイル全体の部分文字列一致」だと、コメントに書いてあるだけで
# 承認済みと判定される (検知器が fail-open する方向の穴)。行頭アンカーの固定
H="$BASE/trust-commented"
make_trust_home "$H" "${ALL_TRUST_ENTRIES[@]}"
: >"$H/.codex/config.toml"
for e in "${ALL_TRUST_ENTRIES[@]}"; do
  printf '# [hooks.state."%s/.codex/hooks.json:%s"] あとで承認する\n' \
    "$H" "$e" >>"$H/.codex/config.toml"
done
out=$(run_trust_checker "$H")
warn_count=$(printf '%s\n' "$out" | LC_ALL=C grep -cF "未承認の codex hook entry:")
check "trust-commented-warn-count" 5 "$warn_count"
check_trust_exit "trust-commented-exit0" "$H"

# ---- trusted_hash の値検証 (issue #214) ----
# キー存在だけを見ていた頃は、「承認後に hooks.json の command を書き換えた」
# = その hook は Untrusted に戻って**実行されていない**、を「承認済み」と
# 誤報告していた。以下はその経路の固定。

# trust-hash-1. 1 entry だけ記録 hash が違う → その entry だけ不一致 WARN。
# 他 entry は静かなまま (「全部不一致にする」退行と「何も見ない」退行の両方を殺す)
H="$BASE/trust-hash-one"; make_trust_home "$H" "${ALL_TRUST_ENTRIES[@]}"
: >"$H/.codex/config.toml"
for e in "${ALL_TRUST_ENTRIES[@]}"; do
  hv=$(trust_expected_hash "$e")
  [ "$e" = "pre_tool_use:0:1" ] && hv="sha256:deadbeef"
  write_trust_entry "$H/.codex/config.toml" "$H/.codex/hooks.json" "$e" "$hv"
done
out=$(run_trust_checker "$H")
check_stdout_has   "trust-hash-one-warns"      "$out" "trusted_hash 不一致: pre_tool_use:0:1"
check_stdout_lacks "trust-hash-one-quiet-rest" "$out" "trusted_hash 不一致: pre_tool_use:0:0"
check_stdout_lacks "trust-hash-one-not-ok"     "$out" "codex-hook-trust: OK"
# 原因ヒントは (a) 承認後の書き換え / (b) codex の payload 仕様変更の**両方**を
# 出し、判別材料 (「変更した覚えがあるか」) を添える。かつては件数で
# 出し分けていたが、**仕様変更でも全件不一致になるとは限らない**ため
# (規則に依存する entry だけが外れる)、1 件不一致に「再承認せよ」だけを出すと
# 誤誘導になる。再承認すると新しい hash が書き戻され証拠が消えるので、
# この誤誘導は取り返しがつかない
check_stdout_has   "trust-hash-one-cause-a"    "$out" "承認後に hooks.json を書き換えた"
check_stdout_has   "trust-hash-one-cause-b"    "$out" "codex の payload 仕様が変わった"
check_stdout_has   "trust-hash-one-evidence"   "$out" "再承認する前に"
check_stdout_has   "trust-hash-one-summary"    "$out" \
  "承認済み 4 / 未承認 0 / hash 不一致 1 / 読み取り不可 0 (対象 5 entry)"
# 未承認が 0 件なので未承認ヒントは出ない (「出さない側」の固定)
check_stdout_lacks "trust-hash-one-no-unapproved-hint" "$out" "codex TUI を開いて承認してください"
check_trust_exit   "trust-hash-one-exit0"      "$H"

# trust-hash-2. **全 entry** の記録 hash が違う → 件数によらず同じ 2 択の
# ヒントが出る (件数で原因を断定しない)
H="$BASE/trust-hash-all"; make_trust_home "$H" "${ALL_TRUST_ENTRIES[@]}"
: >"$H/.codex/config.toml"
for e in "${ALL_TRUST_ENTRIES[@]}"; do
  write_trust_entry "$H/.codex/config.toml" "$H/.codex/hooks.json" "$e" "sha256:deadbeef"
done
out=$(run_trust_checker "$H")
warn_count=$(printf '%s\n' "$out" | LC_ALL=C grep -cF "trusted_hash 不一致:")
check "trust-hash-all-warn-count" 5 "$warn_count"
check_stdout_has   "trust-hash-all-cause-a"  "$out" "承認後に hooks.json を書き換えた"
check_stdout_has   "trust-hash-all-cause-b"  "$out" "codex の payload 仕様が変わった"
check_stdout_has   "trust-hash-all-summary"  "$out" \
  "承認済み 0 / 未承認 0 / hash 不一致 5 / 読み取り不可 0 (対象 5 entry)"
check_stdout_lacks "trust-hash-all-no-unapproved-hint" "$out" "codex TUI を開いて承認してください"
check_trust_exit   "trust-hash-all-exit0"    "$H"

# trust-hash-3 (mutation check). 承認記録は正しいまま **hooks.json 側の command を
# 1 箇所書き換える** → その entry が不一致になる。
# 期待値定数と検査器は同じ payload 仕様から作られているため、定数を並べただけでは
# 「hash が hooks.json の内容から導かれていること」を測れない (両方が同時に
# ずれれば全 pass する)。書き換えた側だけが動く mutation でそこを塞ぐ。
# **command だけを変える** — 1 mutant 1 変数 (matcher や timeout も同時に変えると
# どの入力が hash に効いたのか特定できない)
H="$BASE/trust-hash-mut"; make_trust_home "$H" "${ALL_TRUST_ENTRIES[@]}"
jq '.hooks.PreToolUse[0].hooks[0].command = "bash evil.sh"' \
  "$H/.codex/hooks.json" >"$H/.codex/hooks.json.tmp"
mv "$H/.codex/hooks.json.tmp" "$H/.codex/hooks.json"
out=$(run_trust_checker "$H")
check_stdout_has   "trust-hash-mut-warns"       "$out" "trusted_hash 不一致: pre_tool_use:0:0"
check_stdout_lacks "trust-hash-mut-quiet-rest"  "$out" "trusted_hash 不一致: pre_tool_use:0:1"
check_trust_exit   "trust-hash-mut-exit0"       "$H"

# trust-hash-4. キー行はあるが trusted_hash 行が無い → 「読み取れない」WARN。
# 承認済み側にも未承認側にも倒さない — 読めなかったことを OK に倒すと
# 検知器が fail-open する
H="$BASE/trust-hash-nohash"; make_trust_home "$H"
: >"$H/.codex/config.toml"
for e in "${ALL_TRUST_ENTRIES[@]}"; do
  write_trust_entry "$H/.codex/config.toml" "$H/.codex/hooks.json" "$e" ""
done
out=$(run_trust_checker "$H")
warn_count=$(printf '%s\n' "$out" | LC_ALL=C grep -cF "trusted_hash を読み取れない entry:")
check "trust-hash-nohash-warn-count" 5 "$warn_count"
check_stdout_lacks "trust-hash-nohash-not-unapproved" "$out" "未承認の codex hook entry:"
check_stdout_lacks "trust-hash-nohash-not-ok"         "$out" "codex-hook-trust: OK"
check_trust_exit   "trust-hash-nohash-exit0"          "$H"

# trust-hash-5. **ブロック境界のリセットが効いているか**。trusted_hash 行を持たない
# hooks.state ブロックの直後に別テーブルを置き、そのテーブル側に trusted_hash 行を
# 書く。境界リセット (awk の `index($0, "[") == 1 { cur = "" }`) が無いと、後続
# テーブルの値を前のブロックのものとして拾う = 読み取り不可が「承認済み」に化ける
# fail-open。実 config.toml には [projects.*] / [tui.*] が並ぶので仮想の穴ではない。
# **この形の fixture が 1 本も無かったため、境界行を消した mutant が全 pass していた**
# (code-reviewer が実測)
H="$BASE/trust-hash-boundary"; make_trust_home "$H"
: >"$H/.codex/config.toml"
for e in "${ALL_TRUST_ENTRIES[@]}"; do
  write_trust_entry "$H/.codex/config.toml" "$H/.codex/hooks.json" "$e" ""
  printf '[projects."/x-%s"]\ntrusted_hash = "sha256:deadbeef"\ntrust_level = "trusted"\n\n' \
    "$e" >>"$H/.codex/config.toml"
done
out=$(run_trust_checker "$H")
warn_count=$(printf '%s\n' "$out" | LC_ALL=C grep -cF "trusted_hash を読み取れない entry:")
check "trust-hash-boundary-warn-count" 5 "$warn_count"
check_stdout_lacks "trust-hash-boundary-no-leak" "$out" "trusted_hash 不一致:"
check_trust_exit   "trust-hash-boundary-exit0"   "$H"

# trust-hash-5b. **キー名が `trusted_hash` の接頭辞になる別キー**が同じブロックに
# 先に現れるケース。値の抽出を `index($0, "trusted_hash") == 1` (前方一致) で
# 書くと、そちらを先に拾って正しい記録があるのに不一致と誤報告する。
# codex が将来 trusted_hash_algo のようなキーを足したときに、原因ヒントが
# 「承認後に書き換えた」に倒れて **user を再承認へ誤誘導する** (= 証拠が消える)
H="$BASE/trust-hash-prefixkey"; make_trust_home "$H"
: >"$H/.codex/config.toml"
for e in "${ALL_TRUST_ENTRIES[@]}"; do
  printf '[hooks.state."%s/.codex/hooks.json:%s"]\ntrusted_hash_algo = "sha256:deadbeef"\ntrusted_hash = "%s"\n\n' \
    "$H" "$e" "$(trust_expected_hash "$e")" >>"$H/.codex/config.toml"
done
out=$(run_trust_checker "$H")
check_stdout_has   "trust-hash-prefixkey-ok"     "$out" "codex-hook-trust: OK (5 entry すべて承認済み・hash 一致)"
check_stdout_lacks "trust-hash-prefixkey-nowarn" "$out" "WARN"
check_trust_exit   "trust-hash-prefixkey-exit0"  "$H"

# trust-hash-6. **position が別 position の接頭辞になるケース** (0:1 と 0:10)。
# 引き当ては "<改行><position><TAB>" で行うので TAB が終端として効いているが、
# 上の fixture は 1 group 最大 2 hook なので接頭辞関係が発生せず、この性質が
# 一度も測られていなかった。TAB を落とす退行の向きは fail-open
# (0:1 が 0:10 の承認記録を引く) なので、専用の hooks.json で固定する。
# **承認するのは 0:10 だけ** — 0:1 がそれを引いてしまうなら「未承認」が消える
H="$BASE/trust-prefix"; mkdir -p "$H/.codex"
jq -n '{ hooks: { PreToolUse: [ { matcher: "^Bash$",
  hooks: [ range(11) | { type: "command", command: "bash p\(.).sh" } ] } ] } }' \
  >"$H/.codex/hooks.json"
: >"$H/.codex/config.toml"
write_trust_entry "$H/.codex/config.toml" "$H/.codex/hooks.json" "pre_tool_use:0:10" \
  "sha256:deadbeef"
out=$(run_trust_checker "$H")
# assert 側でも接頭辞衝突を踏まないよう **区切りまで含めて** pin する
# ("… pre_tool_use:0:1" だけだと 0:10 の WARN 行にも grep -F がマッチし、
#  このケースが塞ごうとしている取り違えと同型の罠を assert 側で踏む)
check_stdout_has "trust-prefix-0-1-unapproved" "$out" \
  "未承認の codex hook entry: pre_tool_use:0:1 (codex TUI"
check_stdout_has "trust-prefix-0-10-compared"  "$out" "trusted_hash 不一致: pre_tool_use:0:10"
check_trust_exit "trust-prefix-exit0"          "$H"

# trust-5. ~/.codex が無い (codex 未セットアップ機) → SKIP
H="$BASE/trust-nocodex"; mkdir -p "$H"
out=$(run_trust_checker "$H")
check_stdout_has   "trust-nocodex-skip"   "$out" "codex-hook-trust: SKIP"
check_stdout_lacks "trust-nocodex-nowarn" "$out" "WARN"
check_trust_exit   "trust-nocodex-exit0"  "$H"

# trust-6. hooks.json が無い → SKIP
H="$BASE/trust-nohooksjson"; mkdir -p "$H/.codex"
out=$(run_trust_checker "$H")
check_stdout_has   "trust-nohooksjson-skip"   "$out" "codex-hook-trust: SKIP"
check_stdout_lacks "trust-nohooksjson-nowarn" "$out" "WARN"
check_trust_exit   "trust-nohooksjson-exit0"  "$H"

# trust-6b. hooks.json が壊れた symlink → SKIP ではなく WARN。
# ~/.codex/hooks.json は repo への symlink なので、切れている = hook が
# 1 個も動いていない状態そのもの。-f は symlink を辿るため、-L を先に見ないと
# 「hook 全滅」を未セットアップ機と同じ扱いで静かに見逃す
H="$BASE/trust-dangling"; mkdir -p "$H/.codex"
ln -s "$BASE/does-not-exist.json" "$H/.codex/hooks.json"
out=$(run_trust_checker "$H")
check_stdout_has   "trust-dangling-warns"  "$out" "WARN"
check_stdout_lacks "trust-dangling-noskip" "$out" "codex-hook-trust: SKIP"
check_trust_exit   "trust-dangling-exit0"  "$H"

# trust-7. hooks 定義が空の hooks.json → entry 0 件なので OK (警告を出さない)。
# `.hooks // {}` の fallback が効いていることの固定
H="$BASE/trust-emptyhooks"; mkdir -p "$H/.codex"
printf '{}\n' >"$H/.codex/hooks.json"
: >"$H/.codex/config.toml"
out=$(run_trust_checker "$H")
check_stdout_has   "trust-emptyhooks-zero-entry" "$out" "検査対象の entry が 0 件"
check_stdout_lacks "trust-emptyhooks-nowarn"     "$out" "WARN"
check_trust_exit   "trust-emptyhooks-exit0"      "$H"

# trust-8. hooks.json が JSON として壊れている → WARN (黙って skip しない)。
# codex 自体が hook を読めない = 全 hook が動いていない状態なので、
# この検査が拾いたいものと同型。warn-only 契約 (exit 0) もここで固定する
H="$BASE/trust-brokenjson"; mkdir -p "$H/.codex"
printf 'not json at all\n' >"$H/.codex/hooks.json"
: >"$H/.codex/config.toml"
out=$(run_trust_checker "$H")
check_stdout_has   "trust-brokenjson-warns" "$out" "parse できない"
check_stdout_lacks "trust-brokenjson-not-ok" "$out" "codex-hook-trust: OK"
check_trust_exit   "trust-brokenjson-exit0" "$H"

# trust-9. $HOME 自体が未設定 → SKIP して exit 0。
# 他のケースは常に INTEGRITY_HOME を渡すため $HOME フォールバック経路を一度も
# 踏まず、`${HOME:-}` を `$HOME` に戻す退行が全 pass のまま生き残る。
# set -u 下で unbound variable になると exit 1 = 「全経路 exit 0」の契約が破れ、
# 呼び出し元 run-gate.sh (set -euo pipefail) が毎ターン落ちる。契約を破る唯一の
# 入力なのでここで pin する
nohome_out=$(env -u HOME -u INTEGRITY_HOME bash "$TRUST_CHECKER" 2>/dev/null)
nohome_rc=0
env -u HOME -u INTEGRITY_HOME bash "$TRUST_CHECKER" >/dev/null 2>&1 || nohome_rc=$?
check_stdout_has "trust-nohome-skip" "$nohome_out" "codex-hook-trust: SKIP"
check "trust-nohome-exit0" 0 "$nohome_rc"

# trust-10. 配線: run-gate.sh / Makefile の「コメントでない実行行」から呼ばれている。
# 検査器が正しくても呼ばれていなければ 0 件検知にしかならないので、呼び出し行が
# 消える退行を構造で止める。単なる grep だと直前の説明コメントに名前が残るだけで
# pass するため、行頭が # / @# でない行に限定する
# (tests/hooks-integrity/run-hooks-integrity-tests.sh のケース 13 と同型)
TRUST_REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
LC_ALL=C grep -vE '^[[:space:]]*(#|@#)' "$TRUST_REPO_ROOT/tests/run-gate.sh" \
  | LC_ALL=C grep -q 'verify-codex-hook-trust.sh'
check "trust-wired-in-gate" 0 "$?"
LC_ALL=C grep -vE '^[[:space:]]*(#|@#)' "$TRUST_REPO_ROOT/Makefile" \
  | LC_ALL=C grep -q 'bash tests/integrity/verify-codex-hook-trust.sh'
check "trust-wired-in-makefile" 0 "$?"

# ---- verify-sandbox-exclusion-guard.sh の selftest (issue #267) ----
# この検知器は「hook テストが vacuous pass する 3 経路」を assert するもので、
# 検知器自身が常に PASS を返す退行を防ぐ必要がある (注入口だけあって未検証だと
# 同じ穴を 1 段上に作ることになる)。
EXCL_VERIFIER="${EXCL_VERIFIER_PATH:-$SCRIPT_DIR/verify-sandbox-exclusion-guard.sh}"

run_excl_verifier() {
  # $1=settings.json パス, $2=hook パス, $3=cases パス。exit code を echo
  local rc=0
  INTEGRITY_SETTINGS="$1" INTEGRITY_EXCLUSION_HOOK="$2" INTEGRITY_EXCLUSION_CASES="$3" \
    bash "$EXCL_VERIFIER" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

EXCL_REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
EXCL_HOOK="$EXCL_REPO_ROOT/claude/hooks/guard-sandbox-exclusions.sh"
EXCL_CASES="$EXCL_REPO_ROOT/tests/hooks/guard-sandbox-exclusions.cases.jsonl"
EXCL_SETTINGS="$EXCL_REPO_ROOT/claude/settings.json"

check "excl-baseline-ok" 0 "$(run_excl_verifier "$EXCL_SETTINGS" "$EXCL_HOOK" "$EXCL_CASES")"

# fixture 1: PreToolUse から hook の配線を消す → FAIL
EF="$BASE/excl-settings-unwired.json"
jq '.hooks.PreToolUse = [(.hooks.PreToolUse[] | .hooks |= map(select(.command | test("guard-sandbox-exclusions") | not)))]' \
  "$EXCL_SETTINGS" >"$EF"
check "excl-unwired-detected" 1 "$(run_excl_verifier "$EF" "$EXCL_HOOK" "$EXCL_CASES")"

# fixture 2: excludedCommands に hook の組み込み既定に無い entry を足す → FAIL
EF="$BASE/excl-settings-extra.json"
jq '.sandbox.excludedCommands += ["kubectl *"]' "$EXCL_SETTINGS" >"$EF"
check "excl-builtin-drift-detected" 1 "$(run_excl_verifier "$EF" "$EXCL_HOOK" "$EXCL_CASES")"

# fixture 3: hook から builtin_globs の行が消える (リネーム等) → FAIL
EF="$BASE/excl-hook-no-globs.sh"
LC_ALL=C grep -v '^builtin_globs=(' "$EXCL_HOOK" >"$EF"
check "excl-hook-globs-missing-detected" 1 "$(run_excl_verifier "$EXCL_SETTINGS" "$EF" "$EXCL_CASES")"

# fixture 4: cases ファイルが消える / block ケースを持たない → FAIL
EF="$BASE/excl-cases-no-block.jsonl"
LC_ALL=C grep -v '"expect":"block"' "$EXCL_CASES" >"$EF"
check "excl-cases-no-block-detected" 1 "$(run_excl_verifier "$EXCL_SETTINGS" "$EXCL_HOOK" "$EF")"
check "excl-cases-missing-detected" 1 "$(run_excl_verifier "$EXCL_SETTINGS" "$EXCL_HOOK" "$BASE/does-not-exist.jsonl")"

# fixture 5: 配線: Makefile の「コメントでない実行行」から呼ばれている
LC_ALL=C grep -vE '^[[:space:]]*(#|@#)' "$EXCL_REPO_ROOT/Makefile" \
  | LC_ALL=C grep -q 'bash tests/integrity/verify-sandbox-exclusion-guard.sh'
check "excl-wired-in-makefile" 0 "$?"

echo "----"
echo "integrity selftest: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
