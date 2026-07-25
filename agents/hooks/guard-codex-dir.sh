#!/usr/bin/env bash
#
# PreToolUse hook (Claude Code / Codex CLI 共通): .codex/ ディレクトリへのファイル書き込みをブロックする
# 正本: agents/hooks/guard-codex-dir.sh (claude/hooks/ と codex/hooks/ からは相対 symlink)
#
# 検査対象:
#   - apply_patch: patch 本文中のファイル操作ヘッダー (Add / Update / Delete / Move to) の path
#   - Edit / Write / MultiEdit: path / file_path / filename
#   - NotebookEdit: notebook_path
#   - Bash: command 文字列からトークン抽出し、cwd 内の .codex/ を指す token をブロック
#
# patch 本文中の説明テキストに .codex が含まれるだけなら許可する。
#
# 加えて $HOME/.codex/config.toml (ホーム配下の codex 設定本体) への書き込みも
# ブロックする (issue #190)。sandbox の denyWrite は Bash 経由の書き込みには効くが
# Edit / Write / apply_patch の file 編集 tool には適用されないため、そのままだと
# notify / mcp_servers / hooks フィールド差し替えによる host 側任意コマンド実行が
# 成立する。cwd 判定 (is_protected_project_path) は cwd 配下しか見ないので別判定。
# この追加判定は **file 編集 tool の path のみ** に適用し、Bash token には適用しない
# — Bash 側は block-dangerous-commands.sh が「書き込み文脈」だけを precise に
# ブロックしており、`cat ~/.codex/config.toml` のような読み取りは意図的に許可
# されている (guard 側で token 一致だけで塞ぐとその緩和を壊す)。
#
# Cymulate notify エスケープ（未修正）対策。
#
# exit 0 = 許可, exit 2 = ブロック
#

# exit code を明示的に扱う (0 = 許可 / 2 = ブロック) が、パイプライン失敗や未定義変数の
# silent bypass を防ぐため -e / -u / pipefail をすべて有効化する。fail-safe パスは
# 個別に if ! ... で捕捉して exit 2 を返す。
set -euo pipefail

input=$(cat)

if ! command -v jq &>/dev/null; then
  # jq 不在時はフェイルセーフでブロック
  echo "ブロック: jq 未インストールのため .codex/ 保護を確認できません" >&2
  exit 2
fi

protected_name='.codex'
# cwd 関連の正規化はパス毎ではなく 1 度だけ行う（macOS APFS 想定の case-insensitive 比較）
cwd_lower=$(pwd -P | tr '[:upper:]' '[:lower:]')
# ホーム配下の codex 設定本体。$HOME 未設定環境では空にして判定を無効化する
# (空 prefix が全パスに一致する誤爆を防ぐ)。
home_lower=""
if [[ -n "${HOME:-}" ]]; then
  home_lower=$(printf '%s' "$HOME" | tr '[:upper:]' '[:lower:]')
fi

# パスを小文字化・絶対化・`.`/`..` 畳み込み・symlink 解決した形に正規化して echo する。
# cwd 判定 (is_protected_project_path) と home 判定 (is_protected_home_codex_config)
# の双方が同じ正規化を通るよう共通化してある — 片方だけ正規化が緩いと、そちらが
# バイパス経路になるため。
normalize_path() {
  local path="$1"

  # 引用符 / 先頭の ./ を剥がす
  path="${path#\"}"
  path="${path%\"}"
  path="${path#\'}"
  path="${path%\'}"

  local path_lower
  path_lower=$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')

  # 先頭 ~/ と $HOME / ${HOME} を展開する。file 編集 tool の path は通常絶対パスだが、
  # Bash token 経路と apply_patch ヘッダーでは tilde / $HOME 表記が現れうる。
  if [[ -n "$home_lower" ]]; then
    case "$path_lower" in
      '~'|'~/'*) path_lower="${home_lower}${path_lower#\~}" ;;
      '$home'|'$home/'*) path_lower="${home_lower}${path_lower#\$home}" ;;
      '${home}'|'${home}/'*) path_lower="${home_lower}${path_lower#\$\{home\}}" ;;
    esac
  fi

  # 相対パスは cwd 前置して絶対化
  if [[ "$path_lower" != /* ]]; then
    path_lower="${cwd_lower}/${path_lower#./}"
  fi

  # / . / と / .. / を畳み込み、// を圧縮
  path_lower=$(printf '%s' "$path_lower" | sed -E -e 's#/\./#/#g' -e ':a' -e 's#/[^/]+/\.\.(/|$)#/#g' -e 'ta' -e 's#//+#/#g')

  # 存在する祖先ディレクトリまで遡って pwd -P で symlink を解決 (存在しない suffix は結合)
  case "$path_lower" in
    *[Cc][Oo][Dd][Ee][Xx]*)
      local _try_dir _rest _resolved
      _try_dir=$path_lower
      _rest=
      while [[ -n "$_try_dir" && "$_try_dir" != "/" && ! -d "$_try_dir" ]]; do
        _rest="/${_try_dir##*/}${_rest}"
        _try_dir=${_try_dir%/*}
        [[ -z "$_try_dir" ]] && _try_dir=/
      done
      if [[ -d "$_try_dir" ]]; then
        _resolved=$(cd "$_try_dir" 2>/dev/null && pwd -P) || _resolved=""
        if [[ -n "$_resolved" ]]; then
          path_lower=$(printf '%s' "${_resolved}${_rest}" | tr '[:upper:]' '[:lower:]')
        fi
      fi
      ;;
  esac

  printf '%s' "$path_lower"
}

# パスを解決し「cwd 配下の .codex/」を指しているかを判定する。
# 判定基準: 相対パス / 絶対パスとも「cwd 基準に正規化した結果」が cwd/.codex/ prefix と
# 一致するかで判定する。cwd 外の .codex/ (例: 別プロジェクトの ../other/.codex/) は許可。
is_protected_project_path() {
  local path_lower
  path_lower=$(normalize_path "$1")

  # cwd 配下の .codex/ prefix と一致するか
  case "$path_lower" in
    "$cwd_lower/$protected_name"|"$cwd_lower/$protected_name"/*|"$cwd_lower"/*"/$protected_name"|"$cwd_lower"/*"/$protected_name"/*)
      return 0
      ;;
  esac

  return 1
}

# パスを解決し「$HOME/.codex/config.toml」を指しているかを判定する (issue #190)。
# ディレクトリ全体ではなく config.toml 1 ファイルのみを対象にする — codex CLI は
# sessions/ / history.jsonl / auth.json / *.sqlite 等に正当に書き込む必要があり、
# 攻撃価値が集中しているのは notify / mcp_servers / hooks を持つ config.toml だけ。
is_protected_home_codex_config() {
  # HOME 不明の環境では判定しない (誤爆を避ける。cwd 判定は引き続き効く)
  [[ -n "$home_lower" ]] || return 1

  local path_lower
  path_lower=$(normalize_path "$1")

  # symlink 解決後の $HOME も比較対象に含める。$HOME 自体が symlink (例: /home → /Users)
  # の環境で、正規化済み path と未解決 $HOME の文字列比較が外れるのを防ぐ。
  local home_resolved
  home_resolved=$(cd "$HOME" 2>/dev/null && pwd -P) || home_resolved=""
  if [[ -n "$home_resolved" ]]; then
    home_resolved=$(printf '%s' "$home_resolved" | tr '[:upper:]' '[:lower:]')
  fi

  case "$path_lower" in
    "$home_lower/$protected_name/config.toml") return 0 ;;
  esac
  if [[ -n "$home_resolved" ]]; then
    case "$path_lower" in
      "$home_resolved/$protected_name/config.toml") return 0 ;;
    esac
  fi

  return 1
}

# Bash command を shell メタ文字で分割し、path らしき token を吐き出す
extract_bash_tokens() {
  local cmd="$1"
  # ; & | > < ( ) space tab newline で分割
  printf '%s' "$cmd" | tr ';&|<>()`' '\n' | tr -s ' \t' '\n'
}

# 入力から候補 path を抽出。抽出時 jq が失敗した場合はフェイルセーフでブロック。
# $1 が "edit-only" のときは Bash token を含めない (file 編集 tool の path のみ)。
# home config 判定は「書き込み文脈」を区別できないため、Bash token に適用すると
# `cat ~/.codex/config.toml` のような読み取り許可を壊す。Bash 側の書き込み文脈判定は
# block-dangerous-commands.sh が担当する。
extract_paths() {
  local mode="${1:-all}"
  # apply_patch: tool_input.patch / tool_input.input のファイル操作ヘッダー
  # Edit/Write/MultiEdit: tool_input.path / file_path / filename
  # NotebookEdit: tool_input.notebook_path
  # Bash: tool_input.command を token 分割
  local patch_body direct_paths bash_cmd
  # `if ! caller` 経由で set -e が抑止されるため、jq 失敗は || return 1 で明示検出する。
  patch_body=$(printf '%s' "$input" | jq -r '.tool_input | (.patch? // .input? // empty)') || return 1
  direct_paths=$(printf '%s' "$input" | jq -r '
    .tool_input
    | if type == "object" then
        (.path?, .file_path?, .filename?, .notebook_path?)
      else
        empty
      end
    // empty
  ') || return 1
  bash_cmd=$(printf '%s' "$input" | jq -r '.tool_input | (.command? // empty)') || return 1

  {
    printf '%s\n' "$patch_body" | awk '
      {
        lower = tolower($0)
        if (match(lower, /^\*\*\* (add file|update file|delete file|move to): /)) {
          print substr($0, RLENGTH + 1)
        }
      }
    '
    printf '%s\n' "$direct_paths"
    if [[ "$mode" != "edit-only" && -n "$bash_cmd" ]]; then
      extract_bash_tokens "$bash_cmd"
    fi
  }
}

# 入力解析中の pipeline 失敗は fail-safe でブロック。
if ! candidates=$(extract_paths all); then
  echo "ブロック: tool_input の解析に失敗しました (.codex/ 保護を確認できません)" >&2
  exit 2
fi
if ! edit_candidates=$(extract_paths edit-only); then
  echo "ブロック: tool_input の解析に失敗しました (.codex/ 保護を確認できません)" >&2
  exit 2
fi

# $HOME/.codex/config.toml への file 編集 tool 経由の書き込みを先にブロックする
# (sandbox の denyWrite は Bash にしか効かないため。issue #190)。
home_matched=""
while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  if is_protected_home_codex_config "$p"; then
    home_matched=$p
    break
  fi
done <<<"$edit_candidates"

if [[ -n "$home_matched" ]]; then
  echo "ブロック: ~/.codex/config.toml への書き込みは禁止されています（notify / mcp_servers / hooks 経由の host 側コマンド実行対策、issue #190）" >&2
  exit 2
fi

matched=""
while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  if is_protected_project_path "$p"; then
    matched=$p
    break
  fi
done <<<"$candidates"

if [[ -n "$matched" ]]; then
  echo "ブロック: プロジェクト内の Codex 設定ディレクトリへのファイル操作は禁止されています（Cymulate notify エスケープ対策）" >&2
  exit 2
fi

exit 0
