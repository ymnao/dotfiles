#!/usr/bin/env bash
#
# PreToolUse hook (Codex CLI): パッケージインストール/実行時取得コマンドをブロックする
#
# allowlist 方式: ロックファイルからの復元のみ許可し、依存の追加・実行時取得を
# ブロックする。
#   - npm ci / npm install / npm i（引数なし。npm install の公式 alias 含む）
#   - pnpm install / pnpm i（引数なし）
#   - yarn install（引数なし）
#
# `npm --global install pkg` のようにバイナリとサブコマンドの間にグローバル
# オプションを挟む回避を防ぐため、コマンド文字列を `;`/`&&`/`|` 等で個々の
# セグメントに分割し、各セグメントの先頭バイナリと、それ以降のトークンに
# 「独立トークンとして」含まれる危険サブコマンドを解析する。位置非依存で
# 検出するためグローバルオプション・env 代入・絶対パス起動を挟んでも貫通しない。
#
# exit 0 = 許可, exit 2 = ブロック
#

input=$(cat)

case "$input" in
  *npm*|*npx*|*pnpm*|*yarn*|*bun*|*pip*|*uv*|*poetry*) ;;
  *) exit 0 ;;
esac

if ! command -v jq &>/dev/null; then
  echo "ブロック: jq 未インストールのためパッケージインストールを確認できません" >&2
  exit 2
fi

command=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty')

if [[ -z "$command" ]]; then
  exit 0
fi

block() {
  echo "ブロック: $1" >&2
  exit 2
}

# バイナリ以降のトークン列を解析し、ブロックすべきかを返す。
#   $1: 「常に危険」サブコマンド（独立トークンとして含めばブロック）の ERE
#   $2: 「引数なしなら許可」サブコマンド（復元用途）の ERE。空なら復元許可なし
#   $3-: バイナリ以降のトークン
# 戻り値: 0 = ブロックすべき, 1 = 許可
# 危険サブコマンドは独立トークン一致で検出するため、`npm --global install` の
# ように前置オプションを挟んでも、`--prefix /tmp` のように値付きオプションが
# 挟まっても判定がぶれない（値トークンは既知サブコマンドに一致しないため無視）。
pm_should_block() {
  local always_deny="$1" restore_only="$2"
  shift 2
  local -a toks=("$@")
  local i t restore_idx=-1

  for ((i = 0; i < ${#toks[@]}; i++)); do
    t="${toks[i]}"
    t="${t#[\"\']}"
    t="${t%[\"\']}"
    if [[ -n "$always_deny" && "$t" =~ ^($always_deny)$ ]]; then
      return 0
    fi
    if [[ "$restore_idx" -lt 0 && -n "$restore_only" && "$t" =~ ^($restore_only)$ ]]; then
      restore_idx=$i
    fi
  done

  # 復元系サブコマンド（install/i 等）は引数なしのみ許可。
  # サブコマンド以降に非オプション引数（= 追加するパッケージ名）があればブロック。
  if [[ "$restore_idx" -ge 0 ]]; then
    for ((i = restore_idx + 1; i < ${#toks[@]}; i++)); do
      t="${toks[i]}"
      t="${t#[\"\']}"
      t="${t%[\"\']}"
      case "$t" in
        -*) ;;
        *) return 0 ;;
      esac
    done
  fi

  return 1
}

# npm install と公式 alias（npm help install / install-test の列挙に従う）
npm_restore='install|i|add|in|ins|inst|insta|instal|isnt|isnta|isntal|isntall|install-test|it'

# コマンドをシェル区切り文字でセグメントに分割（各区切りを改行へ置換）
segments=$(printf '%s' "$command" | tr ';&|(){}<>`' $'\n\n\n\n\n\n\n\n\n\n')

while IFS= read -r segment; do
  read -ra toks <<< "$segment"
  [[ ${#toks[@]} -eq 0 ]] && continue

  # 先頭の環境変数代入（VAR=value）を読み飛ばしてバイナリを特定
  idx=0
  while [[ $idx -lt ${#toks[@]} ]]; do
    case "${toks[idx]}" in
      [A-Za-z_]*=*) ((idx++)) ;;
      *) break ;;
    esac
  done
  [[ $idx -ge ${#toks[@]} ]] && continue

  bin="${toks[idx]}"
  bin="${bin#[\"\']}"
  bin="${bin%[\"\']}"
  bin="${bin##*/}"   # 絶対パス起動（/usr/local/bin/npm 等）を正規化
  rest=("${toks[@]:idx+1}")

  case "$bin" in
    npx)
      block "npx は実行時にパッケージを取得し得るため禁止されています"
      ;;
    bunx)
      block "bunx は実行時にパッケージを取得し得るため禁止されています"
      ;;
    uvx)
      block "uvx は実行時にパッケージを取得するため禁止されています"
      ;;
    npm)
      pm_should_block 'exec|x' "$npm_restore" "${rest[@]}" \
        && block "npm install <package> / npm exec 系は禁止されています。パッケージの追加はユーザーに依頼してください"
      ;;
    pnpm)
      pm_should_block 'add|dlx' 'install|i' "${rest[@]}" \
        && block "pnpm add/dlx / pnpm install <package> は禁止されています。パッケージの追加はユーザーに依頼してください"
      ;;
    yarn)
      pm_should_block 'add|dlx' 'install' "${rest[@]}" \
        && block "yarn add/dlx / yarn install <package> は禁止されています。パッケージの追加はユーザーに依頼してください"
      ;;
    bun)
      pm_should_block 'add|a|install|i|x' '' "${rest[@]}" \
        && block "bun add/install/x は許可リスト外です。パッケージ操作はユーザーに依頼してください"
      ;;
    pip|pip3)
      pm_should_block 'install' '' "${rest[@]}" \
        && block "pip install は禁止されています。パッケージの追加はユーザーに依頼してください"
      ;;
    pipx)
      pm_should_block 'install|inject|run' '' "${rest[@]}" \
        && block "pipx install/inject/run はパッケージを取得し得るため禁止されています"
      ;;
    uv)
      # uv add / uv pip install / uv tool install/run をまとめてブロック
      # （uv sync・uv lock・uv run 等の復元/実行系は allowlist 外＝許可）
      pm_should_block 'add|pip|tool' '' "${rest[@]}" \
        && block "uv add / uv pip / uv tool は禁止されています。パッケージの追加はユーザーに依頼してください"
      ;;
    poetry)
      pm_should_block 'add' '' "${rest[@]}" \
        && block "poetry add は禁止されています。パッケージの追加はユーザーに依頼してください"
      ;;
  esac
done <<< "$segments"

exit 0
