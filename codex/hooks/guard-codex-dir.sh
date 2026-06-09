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

case "$input" in
  *.codex*) ;;
  *) exit 0 ;;
esac

if ! command -v jq &>/dev/null; then
  # jq 不在時はフェイルセーフでブロック
  echo "ブロック: jq 未インストールのため .codex/ 保護を確認できません" >&2
  exit 2
fi

# tool_input 全体を文字列化（オブジェクトは JSON エンコード）
payload=$(printf '%s\n' "$input" | jq -r '.tool_input | if type == "string" then . else tostring end')

if [[ -z "$payload" ]]; then
  exit 0
fi

protected_name="$(printf '\056codex')"

is_protected_project_path() {
  local path="$1"
  local cwd

  cwd="$(pwd -P)"
  path="${path#\"}"
  path="${path%\"}"
  path="${path#./}"

  if [[ "$path" = /* ]]; then
    case "$path" in
      "$cwd/$protected_name"|"$cwd/$protected_name"/*|"$cwd"/*"/$protected_name"|"$cwd"/*"/$protected_name"/*)
        return 0
        ;;
    esac
  else
    case "$path" in
      "$protected_name"|"$protected_name"/*|*"/$protected_name"|*"/$protected_name"/*)
        return 0
        ;;
    esac
  fi

  return 1
}

protected_paths=$(
  {
    printf '%s\n' "$payload" \
      | awk '
          /^\*\*\* (Add File|Update File|Delete File|Move to): / {
            sub(/^\*\*\* (Add File|Update File|Delete File|Move to): /, "")
            print
          }
        '
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
