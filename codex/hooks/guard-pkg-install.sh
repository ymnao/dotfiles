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
# 解決してから判定する。command/env/nice/timeout 等の透過ラッパーや bash -c /
# eval はオプション・値・代入を読み飛ばして内側のバイナリまで辿り、xargs/find の
# ような引数注入ラッパーは PM 名出現時点でブロックする。コマンド置換 `$(...)` や
# 変数展開 `$var` は静的に追えないため __dynbin__ にマスクし、それが実行対象に
# 来てパッケージ操作を伴う場合は安全側でブロックする。これによりグローバル
# オプション・env 代入・絶対パス・大文字表記・ラッパー・動的組み立て経由の
# 回避を貫通させない。
#
# exit 0 = 許可, exit 2 = ブロック
#

input=$(cat)

# 早期スクリーニング: PM 名が含まれない入力は即許可。
# 実シェルではトークン内クォート連結（n""pm）・バックスラッシュエスケープ
# （n\pm）が除去された後にバイナリが解決されるため、PM 名の文字間に
# `[\\\\\"']` が挟まる形（np\\m / n""pm 等）も拾う必要がある。JSON エスケープ越し
# の入力では `\` が `\\` に、`"` が `\"` に符号化されるので、両者を許す
# ギャップを含めて grep する。スクリーニング目的の粗マッチでよく、本判定は
# 後段の jq 抽出済み command に対する正規化で精密に行う。
# macOS APFS は既定で case-insensitive のため大文字バイナリも対象にする。
gap='([\\"'"'"']|\\\\|\\")*'
# 動的展開（$ / バックティック）を含む入力は、PM 名を変数・コマンド置換で
# 分割構築している可能性があるため早期 exit しない。本判定側で展開・
# マスク後に判定する。誤検知の代償は通常コマンドの本判定走行のみ。
# python は `python -m pip install` 経由で pip を起動できるためスクリーニング対象。
if ! printf '%s' "$input" | tr '[:upper:]' '[:lower:]' \
    | grep -qE "n${gap}p${gap}m|n${gap}p${gap}x|p${gap}n${gap}p${gap}m|y${gap}a${gap}r${gap}n|b${gap}u${gap}n|p${gap}i${gap}p|u${gap}v|p${gap}o${gap}e${gap}t${gap}r${gap}y|c${gap}o${gap}r${gap}e${gap}p${gap}a${gap}c${gap}k|p${gap}y${gap}t${gap}h${gap}o${gap}n|\\\$|\`"; then
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "ブロック: jq 未インストールのためパッケージインストールを確認できません" >&2
  exit 2
fi

command=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty')

if [[ -z "$command" ]]; then
  exit 0
fi

# 解析より前にシェル意味論で正規化する（n""pm → npm / n\pm → npm 等の回避を
# 解消）。シェルの単語分割と同じ順序で:
#   1. \X → X（バックスラッシュエスケープ解除）
#   2. ' " を全削除（トークン内クォート連結を解消）
# その後、バイナリ名・サブコマンドの大文字表記（NPM INSTALL 等）を取りこぼさない
# よう以降の解析はすべて小文字化した command に対して行う。パッケージ名やパスも
# 小文字化されるが、判定に使うのはバイナリ名とサブコマンド名のみのため無害。
command=$(printf '%s' "$command" \
  | sed -E -e 's/\\(.)/\1/g' -e $'s/[\'"]//g' \
  | tr '[:upper:]' '[:lower:]')

# 単純な変数代入 `var=value` を「コマンド中の $var / ${var}」に静的展開する。
# 例: a=n; b=pm; $a$b install → npm install、
# 　　 a=p; b=npm; core${a}ack $b add → corepack npm add。
# 代入を grep で全て抽出し、各々を sed で順に置換する。bash の通常代入と
# 異なるケース（export FOO=bar / function ローカル等）は対象外。
assignments=$(printf '%s' "$command" \
  | grep -oE '(^|[[:space:];&|])[a-z_][a-z0-9_]*=[^[:space:];&|]*' \
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
      -e "s/\\\$${esc_name}([^a-z0-9_]|\$)/${esc_val}\\1/g")
  done <<< "$assignments"
fi

# 既知の literal 構築イディオムを X に展開してから __dynbin__ マスクへ。
# これにより $(which corepack) pnpm install / $(printf npm) init vite@latest /
# $(echo corepack) use のような動的構築でも、続く X が PM 名なら固定バイナリ
# 分岐に合流して整合的に判定される（X が PM 名でなければ後段の bin 解析でも
# 素通り）。引用符は前段の正規化で既に剥がされているため printf 'X' / "X" も
# printf X として一律マッチする。
command=$(printf '%s' "$command" | sed -E \
  -e 's/\$\([[:space:]]*which[[:space:]]+([a-z][a-z0-9._-]*)[[:space:]]*\)/\1/g' \
  -e 's/\$\([[:space:]]*command[[:space:]]+-v[[:space:]]+([a-z][a-z0-9._-]*)[[:space:]]*\)/\1/g' \
  -e 's/\$\([[:space:]]*type[[:space:]]+-p[[:space:]]+([a-z][a-z0-9._-]*)[[:space:]]*\)/\1/g' \
  -e 's/\$\([[:space:]]*printf[[:space:]]+([a-z][a-z0-9._-]*)[[:space:]]*\)/\1/g' \
  -e 's/\$\([[:space:]]*echo[[:space:]]+([a-z][a-z0-9._-]*)[[:space:]]*\)/\1/g' \
  -e 's/`[[:space:]]*which[[:space:]]+([a-z][a-z0-9._-]*)[[:space:]]*`/\1/g' \
  -e 's/`[[:space:]]*command[[:space:]]+-v[[:space:]]+([a-z][a-z0-9._-]*)[[:space:]]*`/\1/g' \
  -e 's/`[[:space:]]*type[[:space:]]+-p[[:space:]]+([a-z][a-z0-9._-]*)[[:space:]]*`/\1/g' \
  -e 's/`[[:space:]]*printf[[:space:]]+([a-z][a-z0-9._-]*)[[:space:]]*`/\1/g' \
  -e 's/`[[:space:]]*echo[[:space:]]+([a-z][a-z0-9._-]*)[[:space:]]*`/\1/g')

# 残ったコマンド置換 `$(...)` / バックティック / 変数展開 `$var` `${var}` は実行時
# まで中身が決まらず静的に追えない。プレースホルダ __dynbin__ に置換し、それが
# 実行対象（バイナリ位置）に来てパッケージ操作サブコマンドを伴う場合に後段で
# 安全側ブロックする（$npm add / $(printf n)$(printf pm) install 等）。
# 末尾で __dynbin__ の連続（$(printf n)$(printf pm) / $a$b 等）を 1 個に正規化し、
# 動的に分割構築されたバイナリも __dynbin__ 単体として bin 解析に渡す。
command=$(printf '%s' "$command" | sed -E \
  -e 's/\$\([^)]*\)/__dynbin__/g' \
  -e 's/`[^`]*`/__dynbin__/g' \
  -e 's/\$\{[a-z_][a-z0-9_]*\}/__dynbin__/g' \
  -e 's/\$[a-z_][a-z0-9_]*/__dynbin__/g' \
  -e 's/(__dynbin__)+/__dynbin__/g')

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

# 動的バイナリ（__dynbin__）の直後に現れたらブロックするパッケージ操作サブコマンド。
# どの PM か特定できないため install 系 alias に各 PM の追加/取得系を足した和集合。
# PM 特化の語のみを含める。use/prepare/enable/disable/up/pack のような汎用語
# （docker compose up / make prepare 等で使われる）は除外し、代わりに
# $(which X) / `which X` / $(command -v X) を X に literal 展開する正規化で
# 動的 corepack 経路を固定バイナリ分岐に合流させる。run は許可（$(which npm)
# run build のような正当ケースを止めないため）、uv run --with* は別途検出。
dyn_danger="${npm_restore}|a|dlx|exec|inject|tool|pip|create|uvx|bunx"

# 透過的な実行ラッパー: 実行対象がラッパーの先にあり、内側のバイナリがそのまま
# exec される。読み飛ばして「実際に実行されるバイナリ」を解決する。shell の -c や
# eval も含む（bash -c "cmd" / eval cmd は引数以降が実行対象なので内側まで辿れる）。
transparent='command|builtin|exec|eval|env|nohup|nice|setsid|stdbuf|time|timeout|bash|sh|zsh|dash|ksh|mksh|ash|fish|csh|tcsh'

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
  rest=("${toks[@]:BIN_IDX+1}")

  # バイナリトークンに __dynbin__ が混じる（例: core${a}ack → core__dynbin__ack /
  # x$VAR → x__dynbin__）場合は動的構築されたバイナリとして扱う。マスク後の連続
  # は既に sed で 1 個に正規化済みなので、ここでは「含む」かどうかだけ見る。
  case "$bin" in
    *__dynbin__*) bin="__dynbin__" ;;
  esac

  # python -m <module> は <module> を pip/pipx として直接起動できる
  # （python -m pip install X / python -m pipx run X 等）ので、bin が
  # python|python3|pythonX.Y で -m が現れた場合はモジュール名を内側 PM とみなして
  # 再解決する。-m venv / -m unittest 等の無害なモジュールは continue で許可。
  if [[ "$bin" =~ ^python([0-9]+(\.[0-9]+)?)?$ ]]; then
    pyidx=-1
    for ((j = 0; j < ${#rest[@]}; j++)); do
      strip_token "${rest[j]}"
      if [[ "$STRIPPED" == -m ]]; then
        pyidx=$j
        break
      fi
    done
    if [[ $pyidx -ge 0 && $((pyidx + 1)) -lt ${#rest[@]} ]]; then
      strip_token "${rest[pyidx+1]}"
      mod="${STRIPPED##*/}"
      case "$mod" in
        pip|pip3|pipx)
          bin="$mod"
          rest=("${rest[@]:pyidx+2}")
          ;;
        *)
          continue   # -m venv / -m unittest / -m http.server 等は無害として許可
          ;;
      esac
    else
      continue   # python --version / python script.py 等は対象外
    fi
  fi

  # corepack は pnpm/yarn 等の PM を起動・取得するラッパー。
  # - corepack use / corepack install / corepack prepare / corepack enable は
  #   PM の取得・有効化を伴うため allowlist 外として無条件ブロック
  # - corepack pnpm add ... / corepack yarn add ... のような委譲呼び出しは
  #   ラッパーをスキップして内側の PM を再解決し、通常経路で判定する
  if [[ "$bin" == corepack ]]; then
    if [[ ${#rest[@]} -eq 0 ]]; then
      continue
    fi
    strip_token "${rest[0]}"
    sub="${STRIPPED##*/}"
    case "$sub" in
      use|install|prepare|enable|disable|up|pack)
        block "corepack ${sub} は PM の取得/更新/有効化を伴うため禁止されています。パッケージ操作はユーザーに依頼してください"
        ;;
      npm|npx|pnpm|yarn|bun|bunx|pip|pip3|pipx|uv|uvx|poetry)
        bin="$sub"
        rest=("${rest[@]:1}")
        ;;
      *)
        continue   # corepack -v / corepack --version 等は副作用なしで許可
        ;;
    esac
  fi

  # コマンド置換/変数展開で組み立てた実行（バイナリが __dynbin__）は中身を静的に
  # 追えないため、パッケージ操作サブコマンドを伴うものを安全側でブロックする。
  if [[ "$bin" == __dynbin__ ]]; then
    pm_should_block "$dyn_danger" '' "${rest[@]}" \
      && block "コマンド置換/変数展開経由のパッケージマネージャ実行は禁止されています。パッケージ操作はユーザーに依頼してください"
    # uv run --with* に相当する実行時取得フラグも検出する。固定バイナリ側の uv
    # 分岐と同じ判定を __dynbin__ 経由（$(which uv) run --with ... 等）にも適用。
    for ((j = 0; j < ${#rest[@]}; j++)); do
      strip_token "${rest[j]}"
      case "$STRIPPED" in
        --with|--with=*|--with-editable|--with-editable=*|--with-requirements|--with-requirements=*)
          block "コマンド置換/変数展開経由の uv run --with* は実行時にパッケージを取得するため禁止されています"
          ;;
      esac
    done
    continue
  fi

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
      # exec / x / create は initializer や任意パッケージを取得・実行し得るため常に禁止。
      pm_should_block 'exec|x|create' "$npm_restore" "${rest[@]}" \
        && block "npm install <package> / npm exec / npm create は禁止されています。パッケージの追加はユーザーに依頼してください"
      # init は非オプション引数（initializer 名）が来た時のみブロックする。
      # 対話モード `npm init` / フラグのみの `npm init -y` / `--scope=@me` は許可。
      init_seen=0
      for tk in "${rest[@]}"; do
        strip_token "$tk"
        if [[ $init_seen -eq 0 && "$STRIPPED" == "init" ]]; then
          init_seen=1
          continue
        fi
        if [[ $init_seen -eq 1 && "$STRIPPED" != -* ]]; then
          block "npm init <initializer> は実行時にパッケージを取得するため禁止されています"
        fi
      done
      ;;
    pnpm)
      pm_should_block 'add|dlx|create' 'install|i' "${rest[@]}" \
        && block "pnpm add/dlx/create / pnpm install <package> は禁止されています。パッケージの追加はユーザーに依頼してください"
      ;;
    yarn)
      pm_should_block 'add|dlx|create' 'install' "${rest[@]}" \
        && block "yarn add/dlx/create / yarn install <package> は禁止されています。パッケージの追加はユーザーに依頼してください"
      ;;
    bun)
      pm_should_block 'add|a|install|i|x|create' '' "${rest[@]}" \
        && block "bun add/install/x/create は許可リスト外です。パッケージ操作はユーザーに依頼してください"
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
      # （uv sync・uv lock・uv run スクリプト単体等の復元/実行系は許可）。
      pm_should_block 'add|pip|tool' '' "${rest[@]}" \
        && block "uv add / uv pip / uv tool は禁止されています。パッケージの追加はユーザーに依頼してください"
      # uv run --with* / uv run --with-editable / uv run --with-requirements は
      # 実行時にパッケージを取得するため uvx と同じ扱いでブロック。--with は
      # uv tool run でも有効だが上で tool ごとブロック済み。
      for ((j = 0; j < ${#rest[@]}; j++)); do
        strip_token "${rest[j]}"
        case "$STRIPPED" in
          --with|--with=*|--with-editable|--with-editable=*|--with-requirements|--with-requirements=*)
            block "uv run --with* は実行時にパッケージを取得するため禁止されています"
            ;;
        esac
      done
      ;;
    poetry)
      pm_should_block 'add' '' "${rest[@]}" \
        && block "poetry add は禁止されています。パッケージの追加はユーザーに依頼してください"
      ;;
  esac
done <<< "$segments"

exit 0
