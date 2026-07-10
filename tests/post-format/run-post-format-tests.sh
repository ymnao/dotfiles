#!/usr/bin/env bash
set -uo pipefail

# post-format.sh のシナリオテスト。
# 各シナリオで一時 git リポジトリと偽 formatter を作り、PostToolUse 入力 JSON を
# 流して「ファイルが整形されたか / 変更されていないか」と exit code を検証する。
#
# 使い方: run-post-format-tests.sh
#   環境変数 HOOK_PATH で hook の場所を上書きできる
#   (デフォルト: <リポジトリルート>/claude/hooks/post-format.sh)
#
# 依存: bash 3.2+ / jq / git

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
HOOK="${HOOK_PATH:-$REPO_ROOT/claude/hooks/post-format.sh}"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq not installed (Brewfile: brew install jq)" >&2
  exit 1
fi

if [ ! -f "$HOOK" ]; then
  echo "ERROR: hook not found: $HOOK (HOOK_PATH で上書き可)" >&2
  exit 1
fi
for tool in jq git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool is required" >&2; exit 1; }
done

BASE="$(mktemp -d "${TMPDIR:-/tmp}/post-format-tests.XXXXXX")"
cleanup() { [ -n "${BASE:-}" ] && rm -rf "$BASE"; }
trap cleanup EXIT

pass=0
fail=0

ORIG_CONTENT='original content'

make_repo() {
  local dir="$BASE/$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  printf '%s' "$dir"
}

# 偽 prettier: 第 2 引数 (--write <file> の <file>) を FORMATTED で上書き
install_fake_prettier() {
  # $1=repo, $2=exit code (省略時 0)
  local repo="$1" rc="${2:-0}"
  mkdir -p "$repo/node_modules/.bin"
  cat >"$repo/node_modules/.bin/prettier" <<EOF
#!/bin/sh
[ "$rc" = "0" ] && printf 'FORMATTED\n' > "\$2"
exit $rc
EOF
  chmod +x "$repo/node_modules/.bin/prettier"
}

# 偽 ruff: format <file> の <file> を FORMATTED で上書き
install_fake_ruff() {
  local repo="$1"
  mkdir -p "$repo/.venv/bin"
  cat >"$repo/.venv/bin/ruff" <<'EOF'
#!/bin/sh
printf 'FORMATTED\n' > "$2"
exit 0
EOF
  chmod +x "$repo/.venv/bin/ruff"
}

# hook を実行。$1=tool_name, $2=file_path ("-" なら file_path なし)。exit code を echo
run_hook() {
  local json rc=0
  if [ "$2" = "-" ]; then
    json=$(jq -cn --arg t "$1" '{"hook_event_name":"PostToolUse","tool_name":$t,"tool_input":{}}')
  else
    json=$(jq -cn --arg t "$1" --arg f "$2" \
      '{"hook_event_name":"PostToolUse","tool_name":$t,"tool_input":{"file_path":$f}}')
  fi
  printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

check_case() {
  # $1=名前, $2=期待 exit, $3=実際 exit, $4=対象ファイル ("-"なら内容確認なし), $5=期待内容 (formatted|original)
  local ok=1
  [ "$3" != "$2" ] && ok=0
  if [ "$4" != "-" ]; then
    local content
    content=$(cat "$4")
    case "$5" in
      formatted) [ "$content" = "FORMATTED" ] || ok=0 ;;
      original)  [ "$content" = "$ORIG_CONTENT" ] || ok=0 ;;
    esac
  fi
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1))
  else
    echo "FAIL $1: expected_exit=$2 got=$3 expected_content=${5:-n/a}"
    fail=$((fail + 1))
  fi
}

# 1. tool_name が対象外 (Bash) → 何もしない
repo=$(make_repo r01); f="$repo/a.ts"; printf '%s' "$ORIG_CONTENT" >"$f"
install_fake_prettier "$repo"; touch "$repo/.prettierrc"
check_case "skip-bash-tool" 0 "$(run_hook Bash "$f")" "$f" original

# 2. file_path なし → 何もしない
check_case "no-file-path" 0 "$(run_hook Edit -)" - -

# 3. git リポジトリ外のファイル → 何もしない
dir="$BASE/plain"; mkdir -p "$dir"; f="$dir/a.ts"; printf '%s' "$ORIG_CONTENT" >"$f"
check_case "non-git" 0 "$(run_hook Edit "$f")" "$f" original

# 4. prettier: 設定 + ローカル bin あり → 整形される
repo=$(make_repo r04); f="$repo/a.ts"; printf '%s' "$ORIG_CONTENT" >"$f"
install_fake_prettier "$repo"; touch "$repo/.prettierrc"
check_case "prettier-formats" 0 "$(run_hook Edit "$f")" "$f" formatted

# 5. Write ツールでも整形される
repo=$(make_repo r05); f="$repo/a.json"; printf '%s' "$ORIG_CONTENT" >"$f"
install_fake_prettier "$repo"; touch "$repo/.prettierrc"
check_case "write-tool-formats" 0 "$(run_hook Write "$f")" "$f" formatted

# 6. bin はあるが設定なし → 整形しない
repo=$(make_repo r06); f="$repo/a.ts"; printf '%s' "$ORIG_CONTENT" >"$f"
install_fake_prettier "$repo"
check_case "no-config-noop" 0 "$(run_hook Edit "$f")" "$f" original

# 7. package.json の "prettier" キーも設定として扱う
repo=$(make_repo r07); f="$repo/a.ts"; printf '%s' "$ORIG_CONTENT" >"$f"
install_fake_prettier "$repo"; printf '{"prettier":{}}' >"$repo/package.json"
check_case "package-json-config" 0 "$(run_hook Edit "$f")" "$f" formatted

# 8. 設定はあるがローカル bin なし → 整形しない (グローバルにフォールバックしない)
repo=$(make_repo r08); f="$repo/a.ts"; printf '%s' "$ORIG_CONTENT" >"$f"
touch "$repo/.prettierrc"
check_case "no-local-bin-noop" 0 "$(run_hook Edit "$f")" "$f" original

# 9. formatter が失敗しても exit 0・ファイル無傷
repo=$(make_repo r09); f="$repo/a.ts"; printf '%s' "$ORIG_CONTENT" >"$f"
install_fake_prettier "$repo" 1; touch "$repo/.prettierrc"
check_case "formatter-failure-failopen" 0 "$(run_hook Edit "$f")" "$f" original

# 10. python: [tool.ruff] + .venv/bin/ruff → 整形される
repo=$(make_repo r10); f="$repo/a.py"; printf '%s' "$ORIG_CONTENT" >"$f"
install_fake_ruff "$repo"; printf '[tool.ruff]\n' >"$repo/pyproject.toml"
check_case "ruff-formats" 0 "$(run_hook Edit "$f")" "$f" formatted

# 11. python: ruff bin はあるが pyproject に [tool.ruff] なし → 整形しない
repo=$(make_repo r11); f="$repo/a.py"; printf '%s' "$ORIG_CONTENT" >"$f"
install_fake_ruff "$repo"; printf '[project]\nname = "x"\n' >"$repo/pyproject.toml"
check_case "ruff-no-config-noop" 0 "$(run_hook Edit "$f")" "$f" original

# 12. 対象外拡張子 (.sh) → 整形しない
repo=$(make_repo r12); f="$repo/a.sh"; printf '%s' "$ORIG_CONTENT" >"$f"
install_fake_prettier "$repo"; touch "$repo/.prettierrc"
check_case "unmapped-ext-noop" 0 "$(run_hook Edit "$f")" "$f" original

# 13. MultiEdit ツールでも整形される (settings.json の matcher と hook 両方で通ることを保証)
repo=$(make_repo r13); f="$repo/a.ts"; printf '%s' "$ORIG_CONTENT" >"$f"
install_fake_prettier "$repo"; touch "$repo/.prettierrc"
check_case "multiedit-tool-formats" 0 "$(run_hook MultiEdit "$f")" "$f" formatted

# 14. settings.json 側の PostToolUse matcher が MultiEdit を含むこと
# (matcher と hook 実装の両方が MultiEdit に対応していることをまとめて保証する)
SETTINGS="$REPO_ROOT/claude/settings.json"
matcher=$(jq -r '.hooks.PostToolUse[] | select(.hooks[]?.command | test("post-format.sh")) | .matcher' "$SETTINGS")
case "$matcher" in
  *MultiEdit*) pass=$((pass + 1)) ;;
  *) echo "FAIL settings-matcher-contains-multiedit: got=$matcher"; fail=$((fail + 1)) ;;
esac

echo "----"
echo "post-format tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
