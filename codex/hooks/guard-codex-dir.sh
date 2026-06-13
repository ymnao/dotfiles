#!/usr/bin/env bash
#
# PreToolUse hook (Codex CLI): .codex/ ディレクトリへのファイル書き込みをブロックする
#
# apply_patch / Edit / Write 等のファイル編集ツールが .codex/ 配下を操作するのを防ぐ。
# apply_patch はファイル操作ヘッダー、Edit / Write は path 系フィールドだけを検査する。
# patch 本文中の説明テキストに .codex が含まれるだけなら許可する。
#
# Cymulate notify エスケープ（未修正）対策。
#
# exit 0 = 許可, exit 2 = ブロック
#

input=$(cat)

# macOS APFS は既定で case-insensitive のため、早期スクリーニングも
# 大文字小文字を無視する（`.Codex/...` 等の表記でも同一ファイル）。
input_lower=$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')
case "$input_lower" in
  *.codex*) ;;
  *) exit 0 ;;
esac

if ! command -v jq &>/dev/null; then
  # jq 不在時はフェイルセーフでブロック
  echo "ブロック: jq 未インストールのため .codex/ 保護を確認できません" >&2
  exit 2
fi

protected_name="$(printf '\056codex')"
# cwd 関連の正規化はパス毎ではなく 1 度だけ行う（macOS APFS 想定の case-insensitive 比較）
cwd="$(pwd -P)"
cwd_lower=$(printf '%s' "$cwd" | tr '[:upper:]' '[:lower:]')

is_protected_project_path() {
  local path="$1"

  path="${path#\"}"
  path="${path%\"}"
  path="${path#./}"

  local path_lower
  path_lower=$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')

  # 絶対パスは . と .. を解決して正規化する。
  # 正規化しないと /Users/.../$(basename cwd)/../$(basename cwd)/.codex のような
  # .. を含む形が cwd_lower の prefix 比較で素通りする。
  if [[ "$path_lower" = /* ]]; then
    path_lower=$(printf '%s' "$path_lower" | sed -E -e 's#/\./#/#g' -e ':a' -e 's#/[^/]+/\.\.(/|$)#/#g' -e 'ta' -e 's#//+#/#g')
    case "$path_lower" in
      "$cwd_lower/$protected_name"|"$cwd_lower/$protected_name"/*|"$cwd_lower"/*"/$protected_name"|"$cwd_lower"/*"/$protected_name"/*)
        return 0
        ;;
    esac
  else
    case "$path_lower" in
      "$protected_name"|"$protected_name"/*|*"/$protected_name"|*"/$protected_name"/*)
        return 0
        ;;
    esac
  fi

  return 1
}

protected_paths=$(
  {
    # apply_patch の patch 本文を実改行のまま取り出し、ファイル操作ヘッダーから path を抽出。
    # tool_input.patch / tool_input.input は実装により名称が揺れるためどちらも対応する。
    printf '%s\n' "$input" \
      | jq -r '.tool_input | (.patch? // .input? // empty)' \
      | awk '
          {
            lower = tolower($0)
            if (match(lower, /^\*\*\* (add file|update file|delete file|move to): /)) {
              print substr($0, RLENGTH + 1)
            }
          }
        '
    # Edit / Write 等の直接 path フィールドも検査
    printf '%s\n' "$input" \
      | jq -r '
          .tool_input
          | if type == "object" then
              (.path?, .file_path?, .filename?)
            else
              empty
            end
          // empty
        '
  } | while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if is_protected_project_path "$path"; then
      printf '%s\n' "$path"
    fi
  done
)

if [[ -n "$protected_paths" ]]; then
  echo "ブロック: プロジェクト内の Codex 設定ディレクトリへのファイル操作は禁止されています（Cymulate notify エスケープ対策）" >&2
  exit 2
fi

exit 0
