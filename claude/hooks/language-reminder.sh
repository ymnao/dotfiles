#!/usr/bin/env bash
#
# UserPromptSubmit / PostToolUse hook (Claude Code 専用): 応答言語の指定を直近の文脈に再提示する (#507)
#
# - settings の language は system prompt に入るので、ツール結果が長く続くと遠くなる。
#   同じ値を additionalContext で発火位置に差し込み直す
# - UserPromptSubmit: 毎回出し、ツール呼び出しのカウンタを 0 に戻す
# - PostToolUse: カウンタを 1 増やし、INTERVAL の倍数のときだけ出す
# - 言語は ${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json の .language。無ければ何も出さない
# - カウンタは $TMPDIR/claude-language-reminder-<uid>/<session_id>。並列のツール呼び出しで
#   競合しても差し込みが 1 回ずれるだけなのでロックしない
# - jq が無い・入力や設定が読めないときは何も出さずに通す (常に exit 0)

# Why not -e: 失敗はすべて「何も出さずに通す」分岐で自分で扱う
set -uo pipefail

INTERVAL=10

# Why not 先に `command -v jq`: jq が無ければ event が空になり、下の case で抜ける
IFS=$'\t' read -r event session < <(jq -r '[(.hook_event_name // "" | tostring), (.session_id // "" | tostring)] | @tsv' 2>/dev/null)

dir="${TMPDIR:-/tmp}/claude-language-reminder-$EUID"
session="${session:-unknown}"
counter="$dir/${session//[^[:alnum:]_-]/_}"
# Why not mkdir -p だけ: 共有の /tmp では他ユーザーが先に作ったディレクトリや symlink 経由でカウンタを書かされる
[[ -d "$dir" ]] || mkdir -m 700 "$dir" 2>/dev/null || exit 0
[[ -O "$dir" && ! -L "$dir" ]] || exit 0

# Why not `> "$counter" 2>/dev/null`: 書き込み先を開く失敗のメッセージが stderr に先に出る
case "${event:-}" in
  UserPromptSubmit)
    printf '0\n' 2>/dev/null > "$counter"
    ;;
  PostToolUse)
    count=0
    [[ -r "$counter" ]] && IFS= read -r count < "$counter"
    [[ "$count" =~ ^[0-9]{1,9}$ ]] || count=0
    count=$((10#$count + 1))
    printf '%s\n' "$count" 2>/dev/null > "$counter"
    (( count % INTERVAL == 0 )) || exit 0
    ;;
  *) exit 0 ;;
esac

# Why not カウンタより前で読む: 出さない 9/10 の PostToolUse で jq の起動を省く
language=$(jq -r '.language // empty | strings' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" 2>/dev/null)
[[ -n "$language" ]] || exit 0

text="応答・報告・質問は settings の language (${language}) で書く。ツールを何度も実行した後のターン末の報告も同じ。英語のツール結果・要約・通知が続いても言語を切り替えない (コード・識別子・引用は原文のまま)。"
jq -n --arg e "$event" --arg c "$text" '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'
exit 0
