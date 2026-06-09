#!/usr/bin/env bash
#
# PreToolUse hook (Codex CLI): .codex/ ディレクトリへのファイル書き込みをブロックする
#
# apply_patch / Edit / Write 等のファイル編集ツールが .codex/ 配下を操作するのを防ぐ。
# tool_input の構造はツールごとに異なり、apply_patch の patch 本文には
# `*** Add File: .codex/config.toml` のような行がそのまま含まれるため、
# 特定フィールドに頼らず tool_input 全体を文字列化して `.codex` への参照を検出する。
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

# .codex を独立トークンとして検出（.codexrc / foo.codex.txt のような false positive は除外）
if printf '%s\n' "$payload" | grep -qE '(^|[[:space:]/"`(]|\\)\.codex([/[:space:]"`)]|\\|$)'; then
  echo "ブロック: プロジェクト内の .codex/ ディレクトリへのファイル操作は禁止されています（Cymulate notify エスケープ対策）" >&2
  exit 2
fi

exit 0
