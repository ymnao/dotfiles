#!/usr/bin/env bash
#
# claude/settings.json の文字列値に特定ユーザーの home の絶対パス
# (/Users/<name>/ や /home/<name>/、Windows の C:\Users\<name>\) が無いことを検証する。
#
# settings.json は全マシンで共有される (Windows も scripts/link.ps1 で配線する) ので、home の絶対パスは書いたマシンでしか
# 正しくない。`claude plugin marketplace add` が書く extraKnownMarketplaces の path が
# この形で、issue-suggest は既知の注記があっても同じ形で追加された (issue #449)。
# home 配下を指すときは `~/` で書く。
#
# 依存: bash 3.2+ / jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
SETTINGS="${INTEGRITY_SETTINGS:-$REPO_ROOT/claude/settings.json}"

hits=$(jq -r '[paths(strings) as $p | {p: ($p | map(tostring) | join(".")), v: getpath($p)}
  | select(.v | test("(^|[^A-Za-z0-9_.~-])/(Users|home)/[^/]+(/|$)|(^|[^A-Za-z0-9])[A-Za-z]:[\\\\/]Users[\\\\/]"))
  | "\(.p): \(.v)"] | .[]' "$SETTINGS")

if [ -n "$hits" ]; then
  echo "FAIL: $SETTINGS に home の絶対パスがある (~/ で書く):"
  echo "$hits"
  exit 1
fi
echo "verify-settings-no-home-path: PASS"
