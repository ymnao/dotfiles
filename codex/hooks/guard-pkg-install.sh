#!/usr/bin/env bash
#
# PreToolUse hook (Codex CLI): パッケージインストール/実行時取得コマンドをブロックする
#
# allowlist 方式: ロックファイルからの復元のみ許可し、依存の追加・実行時取得を
# ブロックする。
#   - npm ci（ロックファイルからの clean install）
#   - npm install / npm i（オプション・引数なしの素の形のみ。公式 alias 含む）
#   - pnpm install / pnpm i（同上）
#   - yarn install（同上）
#
# 各セグメント（`;`/`&&`/`|` 等で分割）について「実際に実行されるバイナリ」を
# 解決してから判定する。command/env/nice/timeout 等の透過ラッパーや bash -c の
# シェルはオプション・値・代入を読み飛ばして内側のバイナリまで辿り、xargs/find
# のような引数注入ラッパーは PM 名出現時点でブロックする。これによりグローバル
# オプション・env 代入・絶対パス・大文字表記・ラッパー経由の回避を貫通させない。
#
# exit 0 = 許可, exit 2 = ブロック
#

input=$(cat)

# macOS APFS は既定で case-insensitive のため、NPM / NPX / PNPM 等の大文字
# 表記でもバイナリが解決される。早期スクリーニングも本判定も小文字化して行う
# （block-dangerous-commands.sh と同じ方針）。
input_lower=$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')
case "$input_lower" in
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

# バイナリ名・サブコマンドの大文字表記（NPM INSTALL 等）を取りこぼさないよう
# 以降の解析はすべて小文字化した command に対して行う。パッケージ名やパスも
# 小文字化されるが、判定に使うのはバイナリ名とサブコマンド名のみのため無害。
command=$(printf '%s' "$command" | tr '[:upper:]' '[:lower:]')

block() {
  echo "ブロック: $1" >&2
  exit 2
}

# トークン先頭の alias 無効化バックスラッシュと引用符を剥がす（\npm / "npm" → npm）。
# サブシェル fork を避けるため結果はグローバル変数 STRIPPED に格納する。
strip_token() {
  local t="$1"
  while [[ "$t" == \\* ]]; do
    t="${t#\\}"
  done
  t="${t#[\"\']}"
  t="${t%[\"\']}"
  STRIPPED="$t"
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

  # 復元系サブコマンド（install/i 等）は「素の形」のみ許可する。
  # サブコマンドの前後にトークン（グローバルオプション含む）が 1 つでも残れば
  # ブロックする。--global / --save-dev / --package-lock-only /
  # --mode=update-lockfile 等は「ロックファイルからの復元」を超える副作用
  # （global install・lockfile 書き換え等）を持ち得るため、復元したいときは
  # `npm install` / `npm ci` のように素の形で実行させる。
  if [[ "$restore_idx" -ge 0 && ${#toks[@]} -ne 1 ]]; then
    return 0
  fi

  return 1
}

# npm install と公式 alias（npm help install / install-test の列挙に従う）
npm_restore='install|i|add|in|ins|inst|insta|instal|isnt|isnta|isntal|isntall|install-test|it'

# 透過的な実行ラッパー: 実行対象がラッパーの先にあり、内側のバイナリがそのまま
# exec される。読み飛ばして「実際に実行されるバイナリ」を解決する。shell の -c も
# 含む（bash -c "cmd" は -c の次トークン以降が実行対象なので内側まで辿れる）。
transparent='command|builtin|exec|env|nohup|nice|setsid|stdbuf|time|timeout|bash|sh|zsh|dash|ksh|mksh|ash|fish|csh|tcsh'

# 引数注入ラッパー: 実行対象の引数を stdin/置換で後から与えるため、見かけ上
# 「引数なし install」でも実際にはパッケージ名が注入され得る。これらの先に PM 名が
# 現れたら復元例外なしでブロックする（echo x | xargs npm install 等）。
arginjector='xargs|find|parallel'

# 値（次トークン）を取るラッパーオプション。env -u NAME / nice -n N /
# timeout -s SIG / exec -a NAME 等。値を実行対象と誤認しないよう読み飛ばす。
value_opt='-u|-n|-a|-s|-k|-C|--unset|--signal|--kill-after|--chdir|--adjustment'

# グローバル toks / n から、透過ラッパー・オプション・その値・env 代入・裸の数値
# （timeout の duration 等）を読み飛ばし、実際に実行されるバイナリの basename と
# 位置を BIN / BIN_IDX に格納する。見つからなければ BIN="" を返す。
resolve_binary() {
  BIN=""
  BIN_IDX=-1
  local i=0 base expect_value=0
  while [[ $i -lt $n ]]; do
    strip_token "${toks[i]}"
    base="${STRIPPED##*/}"

    if [[ $expect_value -eq 1 ]]; then
      expect_value=0
      ((i++)); continue
    fi
    case "$base" in
      [a-z_]*=*) ((i++)); continue ;;   # env 代入 VAR=value
    esac
    if [[ "$base" =~ ^($transparent)$ ]]; then
      ((i++)); continue
    fi
    if [[ "$base" == -* ]]; then
      [[ "$base" =~ ^($value_opt)$ ]] && expect_value=1
      ((i++)); continue
    fi
    if [[ "$base" =~ ^[0-9]+[smhd]?$ ]]; then   # timeout の duration 等
      ((i++)); continue
    fi
    BIN="$base"
    BIN_IDX=$i
    return 0
  done
  return 1
}

# コマンドをシェル区切り文字でセグメントに分割（各区切りを改行へ置換）
segments=$(printf '%s' "$command" | tr ';&|(){}<>`' $'\n\n\n\n\n\n\n\n\n\n')

while IFS= read -r segment; do
  read -ra toks <<< "$segment"
  n=${#toks[@]}
  [[ $n -eq 0 ]] && continue

  resolve_binary
  bin="$BIN"
  [[ -z "$bin" ]] && continue

  # xargs / find 経由は引数注入で「素の install」も危険なため、PM 名が現れた
  # 時点でブロックする（復元例外を与えない）。
  if [[ "$bin" =~ ^($arginjector)$ ]]; then
    for ((j = BIN_IDX + 1; j < n; j++)); do
      strip_token "${toks[j]}"
      cand="${STRIPPED##*/}"
      case "$cand" in
        npm|npx|pnpm|yarn|bun|bunx|pip|pip3|pipx|uv|uvx|poetry)
          block "xargs/find 経由のパッケージマネージャ実行（${cand}）は禁止されています。パッケージ操作はユーザーに依頼してください"
          ;;
      esac
    done
    continue
  fi

  rest=("${toks[@]:BIN_IDX+1}")

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
