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
# さらに $HOME 配下の別プロジェクトの .codex/ への書き込みもブロックする
# (issue #291)。sandbox の denyWrite は `~/*/**/.codex/**` で home 配下の
# プロジェクトを Bash 経路について止めているが file 編集 tool には効かず、
# cwd 判定は cwd の外を見ないため、cwd 外のプロジェクトが全層素通りしていた。
# これも file 編集 tool の path のみに適用する (理由は上と同じ)。
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
cwd_real=$(pwd -P)
cwd_lower=$(printf '%s' "$cwd_real" | tr '[:upper:]' '[:lower:]')
# ホーム配下の codex 設定本体。$HOME 未設定環境では空にして判定を無効化する
# (空 prefix が全パスに一致する誤爆を防ぐ)。
home_lower=""
# home 系判定が比較すべき $HOME 表記の集合。symlink 解決後の $HOME も持つのは、
# $HOME 自体が symlink (例: /home → /Users) の環境や末尾スラッシュの付く環境で、
# 正規化済み path との文字列比較が外れるのを防ぐため。**「どちらの $HOME 表記と
# 比べるか」は home 系判定に共通の下位問題**なので、判定そのもの (何を保護対象と
# みなすか) からは分けてここに 1 箇所だけ置く — 表記を足したときに片方の判定だけ
# 更新される drift を防ぐ。cwd と同じくパス毎ではなく 1 度だけ解決する。
home_forms=()
if [[ -n "${HOME:-}" ]]; then
  home_lower=$(printf '%s' "$HOME" | tr '[:upper:]' '[:lower:]')
  home_forms=("$home_lower")
  home_resolved_lower=$(cd "$HOME" 2>/dev/null && pwd -P) || home_resolved_lower=""
  if [[ -n "$home_resolved_lower" ]]; then
    home_resolved_lower=$(printf '%s' "$home_resolved_lower" | tr '[:upper:]' '[:lower:]')
    if [[ "$home_resolved_lower" != "$home_lower" ]]; then
      home_forms+=("$home_resolved_lower")
    fi
  fi
fi

# パスを小文字化・絶対化・`.`/`..` 畳み込み・symlink 解決した形に正規化して echo する。
# cwd 判定 / home 判定のすべてがこの 1 つの正規化を通るよう共通化してある
# — 1 つでも正規化が緩いと、そこがバイパス経路になるため。
# $2 に `always` を渡すと symlink 解決を無条件に行う (既定は下記 gate 付き)。
normalize_path() {
  local path="$1"
  local resolve_mode="${2:-gated}"

  # 引用符 / 先頭の ./ を剥がす
  path="${path#\"}"
  path="${path%\"}"
  path="${path#\'}"
  path="${path%\'}"

  # 先頭 ~/ と $HOME / ${HOME} を展開する。file 編集 tool の path は通常絶対パスだが、
  # Bash token 経路と apply_patch ヘッダーでは tilde / $HOME 表記が現れうる。
  # 小文字化は最後にまとめて行う (case-sensitive filesystem 上で symlink 解決が
  # 失敗しないよう、解決までは元の表記を保つ)。
  if [[ -n "${HOME:-}" ]]; then
    case "$path" in
      '~'|'~/'*) path="${HOME}${path#\~}" ;;
      '$HOME'|'$HOME/'*) path="${HOME}${path#\$HOME}" ;;
      '${HOME}'|'${HOME}/'*) path="${HOME}${path#\$\{HOME\}}" ;;
      '$home'|'$home/'*) path="${HOME}${path#\$home}" ;;
      '${home}'|'${home}/'*) path="${HOME}${path#\$\{home\}}" ;;
    esac
  fi

  # 相対パスは cwd 前置して絶対化
  if [[ "$path" != /* ]]; then
    path="${cwd_real}/${path#./}"
  fi

  # / . / と / .. / を畳み込み、// を圧縮
  path=$(printf '%s' "$path" | sed -E -e 's#/\./#/#g' -e ':a' -e 's#/[^/]+/\.\.(/|$)#/#g' -e 'ta' -e 's#//+#/#g')

  # 存在する祖先ディレクトリまで遡って pwd -P で symlink を解決 (存在しない suffix は結合)。
  # gate 付き (既定) の発火条件に「末尾が config.toml」を含めるのが重要 — 名前に
  # codex を含まない symlink (例: `ln -s ~/.codex mylink` → `mylink/config.toml`) で
  # home config 判定を回避できてしまうため。回避経路は実測で確認済み
  # (codex-review security 指摘)。
  #
  # ただし gate は「パス文字列に手掛かりが出る形」しか捕まえない。名前にトークンを
  # 含まない symlink + config.toml 以外の leaf (`mylink/hooks.sh`) は解決されず
  # 素通りする (2026-08-09 に対照付きで実測: 直接指定は block、同じ実体を指す
  # symlink 経由の非 config leaf は allow)。file 編集 tool 経路はこの穴を塞ぐ必要が
  # あるので `always` を渡して無条件に解決する — 候補は通常 1 パスなのでコストは
  # 1 回の cd + pwd -P に収まる。Bash token 経路は 1 コマンドから多数の token が
  # 出るため gate を維持し、そちらは sandbox の denyWrite と
  # block-dangerous-commands.sh が担当する分業に委ねる。
  local _resolve=0
  if [[ "$resolve_mode" == "always" ]]; then
    _resolve=1
  else
    local _gate_probe
    _gate_probe=$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')
    case "$_gate_probe" in
      *codex*|*/config.toml) _resolve=1 ;;
    esac
  fi

  if [[ "$_resolve" -eq 1 ]]; then
    local _try_dir _rest _resolved
    _try_dir=$path
    _rest=
    while [[ -n "$_try_dir" && "$_try_dir" != "/" && ! -d "$_try_dir" ]]; do
      _rest="/${_try_dir##*/}${_rest}"
      _try_dir=${_try_dir%/*}
      [[ -z "$_try_dir" ]] && _try_dir=/
    done
    if [[ -d "$_try_dir" ]]; then
      _resolved=$(cd "$_try_dir" 2>/dev/null && pwd -P) || _resolved=""
      if [[ -n "$_resolved" ]]; then
        path="${_resolved}${_rest}"
      fi
    fi
  fi

  printf '%s' "$path" | tr '[:upper:]' '[:lower:]'
}

# 以下の is_protected_* は **normalize_path 済みの小文字パス**を受け取る
# (呼び出し側のループが 1 候補につき 1 回だけ正規化する)。normalize_path は
# sed / tr / pwd -P の subshell を伴うので、判定の本数だけ再正規化しない。

# 「cwd 配下の .codex/」を指しているかを判定する。
# 判定基準: 相対パス / 絶対パスとも「cwd 基準に正規化した結果」が cwd/.codex/ prefix と
# 一致するかで判定する。cwd 外の .codex/ (例: 別プロジェクトの ../other/.codex/) は
# この判定の対象外 (home 配下は is_protected_home_project_codex_path が見る)。
is_protected_project_path() {
  local path_lower="$1"

  # cwd 配下の .codex/ prefix と一致するか
  case "$path_lower" in
    "$cwd_lower/$protected_name"|"$cwd_lower/$protected_name"/*|"$cwd_lower"/*"/$protected_name"|"$cwd_lower"/*"/$protected_name"/*)
      return 0
      ;;
  esac

  return 1
}

# 「$HOME/.codex/config.toml」を指しているかを判定する (issue #190)。
# ディレクトリ全体ではなく config.toml 1 ファイルのみを対象にする — codex CLI は
# sessions/ / history.jsonl / auth.json / *.sqlite 等に正当に書き込む必要があり、
# 攻撃価値が集中しているのは notify / mcp_servers / hooks を持つ config.toml だけ。
is_protected_home_codex_config() {
  # HOME 不明の環境では判定しない (誤爆を避ける。cwd 判定は引き続き効く)
  [[ -n "$home_lower" ]] || return 1

  local home
  for home in "${home_forms[@]}"; do
    case "$1" in
      "$home/$protected_name/config.toml") return 0 ;;
    esac
  done

  return 1
}

# 「$HOME 配下の別プロジェクトの .codex/」を指しているかを判定する (issue #291)。
# sandbox の denyWrite は `~/*/**/.codex/**` で home 配下のプロジェクトを Bash 経路に
# ついて包括的に止めているが、file 編集 tool には適用されないため、cwd 外の
# プロジェクトが全層素通りしていた。この判定で file 編集 tool 側のスコープを
# sandbox 側に揃える。
#
# $HOME 直下の .codex/ 自身は対象外 — パターンの `*` が空にマッチしても
# `$home/.codex` は `$home//.codex` にならず (normalize_path が // を潰した形と
# 一致しない) 判定を外れる。そこは is_protected_home_codex_config が
# config.toml 1 ファイルだけを止め、codex CLI が正当に書く sessions/ /
# auth.json 等は allow するという別の切り分けを担当している。
#
# home の外 (/tmp / /Volumes 等) は allow のまま — sandbox の
# `~/*/**/.codex/**` も非カバーで、層間の非対称ではなく共通の残余
# (docs/ai-operations.md §10 に記録)。
is_protected_home_project_codex_path() {
  # HOME 不明の環境では判定しない (誤爆を避ける。cwd 判定は引き続き効く)
  [[ -n "$home_lower" ]] || return 1

  local home
  for home in "${home_forms[@]}"; do
    case "$1" in
      "$home"/*"/$protected_name"|"$home"/*"/$protected_name"/*) return 0 ;;
    esac
  done

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

# file 編集 tool 経由の書き込みをブロックする。sandbox の denyWrite は Bash にしか
# 効かないため hook 側で塞ぐ (config.toml 1 ファイル = issue #190、home 配下の
# 別プロジェクト = issue #291、cwd 配下 = 従来から)。
# home 系判定は Bash token には適用しない — Bash 経路の書き込みは sandbox の
# denyWrite (~/.codex/config.toml と ~/*/**/.codex/**) と
# block-dangerous-commands.sh が担当しており、guard 側で token 一致だけで塞ぐと
# `cat ~/.codex/config.toml` のような読み取りの許可を壊す。
# 正規化は 1 候補につき 1 回だけ呼び、symlink 解決は `always` で無条件に行う
# (gate 任せだと名前にトークンを含まない symlink + config.toml 以外の leaf が
# 素通りする。上の normalize_path のコメント参照)。
edit_reason=""
while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  p_lower=$(normalize_path "$p" always)
  if is_protected_home_codex_config "$p_lower"; then
    edit_reason="~/.codex/config.toml への書き込みは禁止されています（notify / mcp_servers / hooks 経由の host 側コマンド実行対策、issue #190）"
    break
  fi
  if is_protected_home_project_codex_path "$p_lower"; then
    edit_reason="ホーム配下のプロジェクトの Codex 設定ディレクトリへのファイル操作は禁止されています（次回 codex 起動時の host 側コマンド実行対策、issue #291）"
    break
  fi
  if is_protected_project_path "$p_lower"; then
    edit_reason="プロジェクト内の Codex 設定ディレクトリへのファイル操作は禁止されています（Cymulate notify エスケープ対策）"
    break
  fi
done <<<"$edit_candidates"

if [[ -n "$edit_reason" ]]; then
  echo "ブロック: ${edit_reason}" >&2
  exit 2
fi

# Bash token を含む全候補に対する cwd 判定。file 編集 tool の path は上のループで
# 解決済みだが、gate 付き正規化でも拾える形はここでも二重に当たる (害は無い)。
matched=""
while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  if is_protected_project_path "$(normalize_path "$p")"; then
    matched=$p
    break
  fi
done <<<"$candidates"

if [[ -n "$matched" ]]; then
  echo "ブロック: プロジェクト内の Codex 設定ディレクトリへのファイル操作は禁止されています（Cymulate notify エスケープ対策）" >&2
  exit 2
fi

exit 0
