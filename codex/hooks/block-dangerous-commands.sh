#!/usr/bin/env bash
#
# PreToolUse hook (Codex CLI): 危険な Bash コマンドをブロックする
# exit 0 = 許可, exit 2 = ブロック (stderr が Codex にフィードバックされる)
#

input=$(cat)

# 早期スクリーニング: 危険コマンド名・codex 文字列が含まれない入力は即許可。
# 実シェルではトークン内のクォート連結（co""dex）・バックスラッシュエスケープ
# （co\dex）が除去された後に解決されるため、これらが文字間に挟まる形も拾う。
# JSON エスケープ越し（\\ / \"）も許す。
# また a=.co; b=dex; touch $a$b/... のように .codex を変数・コマンド置換で
# 分割構築するケースは入力中に codex 文字列が現れないため、動的展開
# （$ / $( / バックティック）を含む入力も本判定に通す（本判定側で展開後に
# 改めて .codex 検出する）。スクリーニング目的の粗判定でよく、誤検知は後段で
# .codex が出ない限り素通りする。
# 大文字バイナリ（CHMOD / .Codex 等）対応のため事前に小文字化する。
input_lower=$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')
gap='([\\"'"'"']|\\\\|\\")*'
if ! printf '%s' "$input_lower" \
    | grep -qE "rm|git|chmod|sudo|c${gap}o${gap}d${gap}e${gap}x|\\\$|\`"; then
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "ブロック: jq 未インストールのためコマンド安全性を確認できません" >&2
  exit 2
fi

command=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty')

if [[ -z "$command" ]]; then
  exit 0
fi

# シェル意味論に従ってコマンドを正規化する（.co""dex / .co\dex / $d=.codex; ...
# のような回避を解消するため、guard-pkg-install.sh と同じ方針）。
#   1. \X → X（バックスラッシュエスケープ解除）
#   2. ' " を全削除（トークン内クォート連結を解消）
# .codex 検出にのみ使う。サブシェルでの正規化結果を $command に上書きする。
command=$(printf '%s' "$command" | sed -E -e 's/\\(.)/\1/g' -e $'s/[\'"]//g')

# 単純な変数代入 `var=value` を「コマンド中の $var / ${var}」に静的展開する。
# 例: d=.codex; touch $d/foo → touch .codex/foo、
# 　　 a=.co; b=dex; touch $a$b/foo → touch .codex/foo（連結も解決される）。
# 代入を grep で全て抽出し、各々を sed で順に置換する。bash の通常代入と
# 異なるケース（export FOO=bar / function ローカル等）は対象外。
assignments=$(printf '%s' "$command" \
  | grep -oE '(^|[[:space:];&|])[A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*' \
  | sed -E 's/^[[:space:];&|]+//')
if [[ -n "$assignments" ]]; then
  while IFS= read -r asgn; do
    [[ -z "$asgn" ]] && continue
    name="${asgn%%=*}"
    val="${asgn#*=}"
    esc_name=$(printf '%s' "$name" | sed 's/[][\\.*^$/]/\\&/g')
    esc_val=$(printf '%s' "$val" | sed 's/[\\&/]/\\&/g')
    command=$(printf '%s' "$command" | sed -E \
      -e "s/\\\$\\{${esc_name}\\}/${esc_val}/g" \
      -e "s/\\\$${esc_name}([^A-Za-z0-9_]|\$)/${esc_val}\\1/g")
  done <<< "$assignments"
fi

# 動的展開（コマンド置換・バックティック・未追跡変数）が残っていて、かつ
# .codex 文字列を含むコマンドは、展開後に .codex 配下を触る可能性があるため
# 安全側で全面ブロックする。Cymulate notify エスケープは静的解析では追えない
# 構築（touch $(pwd)/.codex/... 等）でも成立するため。
# ただし $HOME / ${HOME} / ~ はホーム配下の .codex を指す合法経路（後段の token
# 走査が許可する）なので、これらだけが残っている場合は誤検知しないよう除外する。
# 小文字化前提では $HOME も $home に変わるが、ここでは入力が混在のため両方除外。
residual=$(printf '%s' "$command" | sed -E \
  -e 's/\$\{home\}//Ig' \
  -e 's/\$home([^A-Za-z0-9_]|$)/\1/Ig')
if printf '%s' "$residual" | grep -qi '\.codex' \
   && printf '%s' "$residual" | grep -qE '\$\(|`|\$[A-Za-z_{]'; then
  echo "ブロック: 動的展開を含む .codex/ 参照は安全側で禁止されています（Cymulate notify エスケープ対策）" >&2
  exit 2
fi

# 動的展開がファイル書き込み・ディレクトリ操作系コマンドの引数に現れる場合、
# その中身が `.codex` を構築する可能性があるため安全側でブロックする。
# 例: touch .$(printf codex)/config.toml → 静的に .codex 検出できないが、
# 実行時に .codex/config.toml になる。$HOME / ${HOME} / ~ は上で除外済み。
write_cmds='touch|mkdir|install|cp|mv|dd|tee|ln|printf'
if printf '%s' "$residual" | grep -qE '\$\(|`|\$[a-zA-Z_{]' \
   && printf '%s' "$residual" | grep -qiE "(^|[;&|({\`[:space:]])($write_cmds)([[:space:]]|[;&|)}\`]|$)"; then
  echo "ブロック: 動的展開を含む書き込み系コマンドは安全側で禁止されています（.codex 構築の可能性、Cymulate notify エスケープ対策）" >&2
  exit 2
fi

# 動的展開と書き込み系リダイレクト演算子の組み合わせも同様に安全側ブロックする。
# 例: echo x > .$(echo codex)/config.toml → 実行時に .codex/config.toml へ書き込み。
# 対象演算子: > / >> / >| / &> / &>> / N> / N>> （N は fd 番号）
# 入力リダイレクト < / << / <<< と fd コピー >& は対象外（書き込み先がファイルでない）。
if printf '%s' "$residual" | grep -qE '\$\(|`|\$[a-zA-Z_{]' \
   && printf '%s' "$residual" | grep -qE '(^|[^&0-9])>[>|]?[^&]|&>>?[^&]|[0-9]+>>?[^&]'; then
  echo "ブロック: 動的展開を含む書き込み系リダイレクトは安全側で禁止されています（.codex 構築の可能性、Cymulate notify エスケープ対策）" >&2
  exit 2
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
  # cwd 配下の絶対パスは相対化してから判定する（mkdir /abs/cwd/.codex 等の回避を防ぐ）。
  # cwd 外の絶対パスだけが /* で許可される。guard-codex-dir.sh と同じ基準。
  token="${token#"$cwd_lower"/}"

  case "$token" in
    "~/$protected_name"|"~/$protected_name"/*|"\$home/$protected_name"|"\$home/$protected_name"/*|/*)
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
