#!/usr/bin/env bash
#
# PreToolUse hook (Codex CLI): 危険な Bash コマンドをブロックする
# exit 0 = 許可, exit 2 = ブロック (stderr が Codex にフィードバックされる)
#

input=$(cat)

# 早期スクリーニングも case-insensitive（macOS APFS 想定で `.Codex` 等も拾う）
input_lower=$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')
case "$input_lower" in
  *rm*|*git*|*codex*|*chmod*|*sudo*) ;;
  *) exit 0 ;;
esac

if ! command -v jq &>/dev/null; then
  echo "ブロック: jq 未インストールのためコマンド安全性を確認できません" >&2
  exit 2
fi

command=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty')

if [[ -z "$command" ]]; then
  exit 0
fi

# --- 破壊的ファイル操作 ---
rm_rf_pattern='(^|[;&|({`[:space:]])rm[[:space:]]+('
rm_rf_pattern+='([^;&|]*[[:space:]])?-[a-zA-Z]*[rR][a-zA-Z]*f[a-zA-Z]*'
rm_rf_pattern+='|([^;&|]*[[:space:]])?-[a-zA-Z]*f[a-zA-Z]*[rR][a-zA-Z]*'
rm_rf_pattern+='|([^;&|]*[[:space:]])?(--recursive|-[a-zA-Z]*[rR][a-zA-Z]*)[^;&|]*(--force|[[:space:]]-[a-zA-Z]*f[a-zA-Z]*)'
rm_rf_pattern+='|([^;&|]*[[:space:]])?(--force|-[a-zA-Z]*f[a-zA-Z]*)[^;&|]*(--recursive|[[:space:]]-[a-zA-Z]*[rR][a-zA-Z]*)'
rm_rf_pattern+=')'
if printf '%s\n' "$command" | grep -qE "$rm_rf_pattern"; then
  if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])rm[[:space:]].*[[:space:]]+(/|~/|\$HOME|\.\.(/|[[:space:]]|[;&|)}`]|$)|\./?([[:space:]]|[;&|)}`]|$))'; then
    echo "ブロック: rm -rf で危険なパスが指定されています" >&2
    exit 2
  fi
fi

# --- Git 破壊的操作 ---
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])git[[:space:]]+push[[:space:]]+([^;&|]*[[:space:]])?(--force|--force-with-lease(=[^[:space:]]*)?|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: git push --force は禁止されています" >&2
  exit 2
fi

if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])git[[:space:]]+reset[[:space:]]+--hard([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: git reset --hard は禁止されています" >&2
  exit 2
fi

# --- プロジェクト内 [.]codex ディレクトリへの参照をブロック ---
# 書き込みコマンドの列挙ではすべてのリダイレクト/エイリアスを網羅できないため、
# コマンド全体に対して相対パスの [.]codex を独立トークンとして検出する。
# 例: `> .codex/config.toml`, `install -d .codex`, `printf x > .codex/config.toml` 等
#
# macOS APFS は既定で case-insensitive のため、`.Codex` 等の表記でも
# 同一ファイルにアクセスできる。検出は大文字小文字を無視して行う。
if printf '%s\n' "$command" | grep -qiE '(^|[;&|({`[:space:]>]|[.]\/)[.]codex([\/[:space:]"`)]|$)'; then
  echo "ブロック: プロジェクト内の .codex/ ディレクトリへの参照は禁止されています（Cymulate notify エスケープ対策）" >&2
  exit 2
fi

protected_name="$(printf '\056codex')"
# command を 1 度だけ小文字化し、それ以降は全部小文字で比較する
# （macOS APFS 想定で `.Codex` 等も拾う）。`$HOME` はシェル展開されない
# リテラル文字列なので、小文字化された `$home` をパターンに含めて許可判定する。
command_lower=$(printf '%s' "$command" | tr '[:upper:]' '[:lower:]')
cwd_lower=$(printf '%s' "$(pwd -P)" | tr '[:upper:]' '[:lower:]')
normalized_command=$(printf '%s\n' "$command_lower" | tr ';&|(){}<>' '        ')
for token in $normalized_command; do
  token="${token#\"}"
  token="${token%\"}"
  token="${token#\'}"
  token="${token%\'}"
  token="${token#./}"

  case "$token" in
    # ホーム配下の絶対表記は許可
    "~/$protected_name"|"~/$protected_name"/*|"\$home/$protected_name"|"\$home/$protected_name"/*)
      continue
      ;;
    # cwd 配下の絶対パス経由 .codex はブロック（mkdir /abs/cwd/.codex 等の回避を防ぐ）
    "$cwd_lower/$protected_name"|"$cwd_lower/$protected_name"/*|"$cwd_lower"/*"/$protected_name"|"$cwd_lower"/*"/$protected_name"/*)
      echo "ブロック: プロジェクト内の .codex/ ディレクトリへの参照は禁止されています（Cymulate notify エスケープ対策）" >&2
      exit 2
      ;;
    # cwd 外の絶対パスは許可
    /*)
      continue
      ;;
    "$protected_name"|"$protected_name"/*|*"/$protected_name"|*"/$protected_name"/*)
      echo "ブロック: プロジェクト内の .codex/ ディレクトリへの参照は禁止されています（Cymulate notify エスケープ対策）" >&2
      exit 2
      ;;
  esac
done

# --- chmod 777 ---
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])chmod[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*777([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: chmod 777 は禁止されています" >&2
  exit 2
fi

# --- sudo ---
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])sudo[[:space:]]'; then
  echo "ブロック: sudo は禁止されています" >&2
  exit 2
fi

exit 0
