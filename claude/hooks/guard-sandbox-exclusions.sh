#!/usr/bin/env bash
#
# PreToolUse hook (Claude Code 専用): sandbox の excludedCommands にマッチする
# コマンドを、他のコマンドと同じ Bash 呼び出しに混ぜることをブロックする。
# exit 0 = 許可, exit 2 = ブロック (stderr がエージェントにフィードバックされる)
#
# 正本: claude/hooks/guard-sandbox-exclusions.sh (実体。symlink ではない)
# codex には excludedCommands 相当の機構が無いため codex/hooks/ には置かない。
#
# ## なぜ必要か (issue #267)
#
# Claude Code の Bash tool は 1 呼び出しをまるごと sandbox 内か外のどちらかで
# 実行する all-or-nothing 設計で、`sandbox.excludedCommands` のマッチは
# **パース済み sub-command 単位・順序非依存**に行われる。したがって compound 行の
# どこか 1 つがマッチすると、**その行全体**が sandbox 外で走る。
#
# 実測 (2026-08-04 / Claude Code 2.1.212 / macOS Seatbelt。`~/` は allowWrite 外):
#   touch ~/x.tmp                                → Operation not permitted (sandbox 内)
#   brew --version > /dev/null && touch ~/x.tmp  → 成功 (sandbox 外)
#   touch ~/x.tmp; gh --version                  → 成功 (sandbox 外。gh は後ろでもよい)
#   echo "... gh --version ..."; touch ~/x.tmp   → Operation not permitted (文字列言及は非マッチ)
#
# これは Claude Code の仕様であり、除外コマンドを「単独コマンドのときだけ除外する」
# 指定方法は上流に存在しない (2.1.212 時点)。よって hook 側で単独実行を強制する。
#
# ## 効かないもの (意図的な残余リスク)
#
# 除外コマンドを **単独行**で実行する場合 (`gh api ... > ~/file` 等) は引き続き
# sandbox 外で走る。`gh *` は macOS Keychain が sandbox 内から届かないため
# excludedCommands から外せず (実測: sandbox 内の gh は "token in keyring is invalid")、
# この残余は除去できない。詳細は docs/ai-operations.md §10。
#

set -euo pipefail

input=$(cat)

if ! command -v jq &>/dev/null; then
  # jq 不在時はフェイルセーフでブロック (block-dangerous-commands.sh と同じ姿勢)
  echo "ブロック: jq 未インストールのため sandbox 除外コマンドの混在を確認できません" >&2
  exit 2
fi

command=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

if [[ -z "$command" ]]; then
  exit 0
fi

# --- 除外コマンドのリスト取得 -------------------------------------------------
# 正本は実際に効いている設定 ($HOME/.claude/settings.json)。読めない / 壊れている
# 場合だけ組み込み既定にフォールバックする。フォールバックが必要なのは
# tests/run-hook-tests.sh が隔離 HOME で hook を実行するため — 実設定に依存すると
# テスト結果が実ユーザー環境の設定に左右される。
builtin_globs=('docker *' 'gh *' 'brew *' 'pnpm test:e2e *')

globs=()
settings="${HOME:-}/.claude/settings.json"
if [[ -n "${HOME:-}" && -r "$settings" ]]; then
  while IFS= read -r g; do
    [[ -n "$g" ]] && globs+=("$g")
  done < <(jq -r '.sandbox.excludedCommands // [] | .[]' "$settings" 2>/dev/null || true)
fi
if [[ ${#globs[@]} -eq 0 ]]; then
  globs=("${builtin_globs[@]}")
fi

# glob からリテラル前置語だけを取り出す ("gh *" → "gh", "pnpm test:e2e *" → "pnpm test:e2e")。
prefixes=()
for g in "${globs[@]}"; do
  p=${g%%[*?[]*}          # 最初の glob メタ文字以降を落とす
  p=${p%"${p##*[! ]}"}    # 末尾空白を落とす
  [[ -n "$p" ]] && prefixes+=("$p")
done
[[ ${#prefixes[@]} -eq 0 ]] && exit 0

# --- コマンド行の分解 ---------------------------------------------------------
# 完全なシェルパースは書かない (bash 3.2)。誤りは「分割を促す」方向に倒す。
#
# 1) リダイレクト複製子 (2>&1 / >&2 / &> 等) を除去する。`&` を含むため
#    そのまま区切り文字扱いすると `gh pr view 2>&1` 単独が compound に見える。
# 2) クォート span を除去する。シェル上でも区切り文字にならないため除去は正しい。
#    - シングルクォート内は展開が起きないので無条件に除去する
#      (`gh ... --jq '.[] | .name'` のパイプで誤ブロックしないため)
#    - ダブルクォート内は `$` / バックティックを含まないものだけ除去する
#      (`"$(gh x)"` は実際にコマンドを起動するので区切りとして残す)
# 3) 制御演算子・コマンド置換・グループ化の文字を改行に変え、segment に割る。
sanitized=$(printf '%s' "$command" \
  | sed -e 's/[0-9]*>&[0-9-]*//g' -e 's/&>>*//g' \
  | sed -e "s/'[^']*'//g" \
  | sed -e 's/"[^"$`]*"//g')

segments=$(printf '%s' "$sanitized" | tr ';|&(){}`' '\n')

seg_count=0
while IFS= read -r seg; do
  seg=${seg#"${seg%%[![:space:]]*}"}
  [[ -n "$seg" ]] && seg_count=$((seg_count + 1))
done <<< "$segments"

# 単独コマンド (区切りが無い) はブロック対象外。除外コマンド自体はこの形で使う。
[[ $seg_count -le 1 ]] && exit 0

# --- segment ごとの照合 -------------------------------------------------------
matched=""
while IFS= read -r seg; do
  seg=${seg#"${seg%%[![:space:]]*}"}
  [[ -z "$seg" ]] && continue
  # 先頭の `!` と 環境変数代入 (VAR=value) を剥がしてコマンド語に到達する
  seg=${seg#!}
  seg=${seg#"${seg%%[![:space:]]*}"}
  while [[ "$seg" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+ ]]; do
    seg=${seg#"${BASH_REMATCH[0]}"}
  done
  for p in "${prefixes[@]}"; do
    if [[ "$seg" == "$p" || "$seg" == "$p "* ]]; then
      matched="$p"
      break 2
    fi
  done
done <<< "$segments"

[[ -z "$matched" ]] && exit 0

cat >&2 <<EOF
ブロック: sandbox 除外コマンド "$matched" が他のコマンドと同じ Bash 呼び出しに混ざっています。

Claude Code は 1 つの Bash 呼び出しをまるごと sandbox 内か外で実行するため、
excludedCommands にマッチする sub-command が 1 つでもあると **行全体**が
sandbox 外で走ります (順序は問わない。issue #267)。

対処: "$matched" を単独の Bash 呼び出しに分け、他のコマンドは別の呼び出しで実行してください。
  NG: $matched ... && other-command
  OK: $matched ...        (1 回目)
      other-command       (2 回目)
EOF
exit 2
