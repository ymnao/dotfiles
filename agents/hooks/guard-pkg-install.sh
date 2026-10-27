#!/usr/bin/env bash
#
# PreToolUse hook (Claude Code / Codex CLI 共通): パッケージインストール/実行時取得コマンドをブロックする
# 正本: agents/hooks/guard-pkg-install.sh
# (claude/hooks/ と codex/hooks/ からは相対 symlink で参照される)
#
# allowlist 方式: ロックファイルからの復元のみ許可し、依存の追加・実行時取得を
# ブロックする。
#   - pnpm install / pnpm i / pnpm install-test / pnpm it（引数なしの素の形と、lockfile を書き換えない
#     --frozen-lockfile / --offline / --prefer-offline / --ignore-scripts のみ）
#   - yarn install（引数・オプションなしの素の形のみ）
#   - npm / npx は pnpm への一本化のため全サブコマンド禁止
#
# 各セグメント（`;`/`&&`/`|` 等で分割）について「実際に実行されるバイナリ」を
# 解決してから判定する。command/env/nice/timeout 等の透過ラッパーや bash -c /
# eval はオプション・値・代入を読み飛ばして内側のバイナリまで辿り、xargs/find の
# ような引数注入ラッパーは PM 名を引数に取った時点でブロックする。コマンド置換
# `$(which pnpm)` は中身の PM 名に置き換えて判定し、中身そのものも別に判定する。
# これによりグローバルオプション・env 代入・絶対パス・大文字表記・ラッパー経由の
# 形を貫通させない。
#
# 守る範囲: agent がふだん書く形を判断の場で止めて user へ回す guardrail であり、セキュリティ
# 境界ではない。変数で組み立てたバイナリ (`$pm add`)・空白を含む引用付きの値 (`FOO="a b" pnpm add`)・
# ヒアストリングで渡すコマンドは見ない。スクリプトファイル・インタプリタ (`python3 -c` 等)・`make`・
# エンコードを経由する形は PM 名がシェルのバイナリ位置に現れないので、文字列の解析を深くしても
# 閉じない。その備えは
# package manager 自身の設定 (#485) と入った状態の検査 (global は #484、project は lockfile の
# diff) の側に置く。sandbox は npm / PyPI の registry を allowedDomains で通すので、この備えには
# 数えない。
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
# コマンド置換（$( / バックティック）を含む入力は、PM 名を置換の出力で
# 組み立てている (`$(printf %s n pm)`) 可能性があるため早期 exit しない。本判定側で
# 中身を解析する。誤検知の代償は通常コマンドの本判定走行のみ。
# python は `python -m pip install` 経由で pip を起動できるためスクリーニング対象。
if ! printf '%s' "$input" | tr '[:upper:]' '[:lower:]' \
    | grep -qE "n${gap}p${gap}m|n${gap}p${gap}x|p${gap}n${gap}p${gap}m|y${gap}a${gap}r${gap}n|b${gap}u${gap}n|p${gap}i${gap}p|u${gap}v|p${gap}o${gap}e${gap}t${gap}r${gap}y|c${gap}o${gap}r${gap}e${gap}p${gap}a${gap}c${gap}k|p${gap}y${gap}t${gap}h${gap}o${gap}n|c${gap}a${gap}r${gap}g${gap}o|g${gap}e${gap}m|b${gap}u${gap}n${gap}d${gap}l|g${gap}o([^a-z0-9_-]|\$)|\\\$\\(|\`"; then
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "ブロック: jq 未インストールのためパッケージインストールを確認できません" >&2
  exit 2
fi

block() {
  echo "ブロック: $1" >&2
  exit 2
}

command=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty')

if [[ -z "$command" ]]; then
  exit 0
fi

# 行継続 `\⏎` は shell が単語分割より前に取り除くので、同じく先に結合する。
# 行末の `\` が奇数個のときだけ結合するのは、`\\⏎` (リテラルの `\` + 改行 = コマンド区切り)
# の次の行を前の行の引数に吸い込まないため。単一引用符の中でも結合するが、そこは実行され
# ない文字列か、`bash -c` の内側で同じ結合を受ける文字列なので判定は変わらない。
# コメント (`# x \⏎`) の `\` は行継続にならず次の行が実行されるので、`#` が語の先頭に
# ある行は結合しない。その `#` が引用符の中 (`echo "#"; pnpm \⏎add foo`) なら結合が
# 正しいので、結合を止めた行があったときは全部結合した版も末尾に足して両方を判定する。
if [[ "$command" == *$'\\\n'* ]]; then
  command=$(printf '%s\n' "$command" | awk '{
    n = match($0, /\\+$/) ? RLENGTH : 0
    body = substr($0, 1, length($0) - 1)
    if (n % 2) { fbuf = fbuf body } else { full = full fbuf $0 "\n"; fbuf = "" }
    if (n % 2 && $0 !~ /(^|[[:blank:];&|()])#/) { buf = buf body } else { if (n % 2) kept = 1; print buf $0; buf = "" }
  } END {
    if (buf != "") print buf
    if (kept) printf "%s%s\n", full, fbuf
  }')
fi

# 値（次トークン）を取るラッパーオプション。env -u NAME / nice -n N /
# timeout -s SIG / exec -a NAME 等。値を実行対象と誤認しないよう読み飛ばす。
value_opt='-u|-n|-a|-s|-k|-C|--unset|--signal|--kill-after|--chdir|--adjustment'

# 解析より前にシェル意味論で正規化する（n""pm → npm / n\pm → npm 等の回避を
# 解消）。シェルの単語分割と同じ順序で:
#   0. fd 番号付きリダイレクト（2>&1 / 2>/dev/null）の数字を落とす
#      （リダイレクト本体はセグメント分割の直前に先ごと消す）
#   1. \X → X（バックスラッシュエスケープ解除）
#   2. ' " を全削除（トークン内クォート連結を解消）
# 0 を 1・2 より前に置き、リダイレクト先の直後を空白・行末・区切りに限るのは
# `"2">x` / `\2>x`（bash では引数 `2`）と、引用符の中の ` 2>x"` を落とさないため。
# 直後の 1 文字を消費するので `/g` 1 回では `1>x 2>&1` の 2 つ目を拾えず、2 回かける
# （1 回目の後は残りが隣り合わない。ループにしないのは連続入力で 2 乗になるため）。
# その後、バイナリ名・サブコマンドの大文字表記（NPM INSTALL 等）を取りこぼさない
# よう以降の解析はすべて小文字化した command に対して行う。パッケージ名やパスも
# 小文字化されるが、判定に使うのはバイナリ名とサブコマンド名のみのため無害。
fd_num_re=$'s/(^|[[:blank:]])[0-9]+((>>|>[|]|>&|<&|<>|>|<)[^][:blank:];&|()<>{}$`\'"\\\\]+)([[:blank:]]|$|[;|&()])/\\1\\2\\4/g'
command=$(printf '%s' "$command" \
  | sed -E -e "$fd_num_re" -e "$fd_num_re" \
    -e 's/\\(.)/\1/g' -e $'s/[\'"]//g' \
  | tr '[:upper:]' '[:lower:]')

# コマンド置換 `$(...)` / バックティックの中身を解析し、PM 名 token を含むものは
# その PM 名 1 語に置き換える。which/command -v/type -p/printf/echo 等の具体的な
# イディオムに依存せず、「$(...) が PM 名を出力する形」を固定バイナリ分岐に合流させる。
#   $(which corepack)       → corepack
#   $(printf npm)           → npm
#   $(printf %s npm)        → npm（中身の "%s" は token として PM 名と一致せず）
#   $(command -v -- npm)    → npm
#   $(cat /dev/null)        → __subst__（PM 名 token なし）
pm_token_re='^(npm|npx|pnpm|yarn|bun|bunx|pip|pip3|pipx|uv|uvx|poetry|corepack|python|python3|python[0-9.]+|cargo|gem|bundle|bundler|go)$'

# 中身の各 token が PM 名と一致すれば即その PM 名を、また printf の引数列
# （%* / -* を除外）を連結した文字列が PM 名と一致すればその PM 名を標準出力に返す。
# どちらも該当しなければ PM 名でない 1 語 __subst__ を返す。
resolve_cmd_subst() {
  local inner="$1"
  local first_pm="" concat=""
  local is_printf=0
  set -- $inner
  if [[ "${1:-}" == "printf" ]]; then
    is_printf=1
    shift
  fi
  for tok in "$@"; do
    case "$tok" in
      -*) continue ;;
      %*) continue ;;          # printf format spec (%s / %s\n / %-10s 等)
    esac
    if [[ -z "$first_pm" && "$tok" =~ $pm_token_re ]]; then
      first_pm="$tok"
    fi
    [[ $is_printf -eq 1 ]] && concat+="$tok"
  done
  if [[ -n "$first_pm" ]]; then
    printf '%s' "$first_pm"
  elif [[ -n "$concat" && "$concat" =~ $pm_token_re ]]; then
    printf '%s' "$concat"
  else
    printf '%s' "__subst__"
  fi
}

# 置き換えた 1 語は置換の外の文脈 (`$(which npm) install` のバイナリ位置) の判定に使い、
# 中身そのものは実行されるので別の行として末尾に足して判定に残す (`echo $(pnpm add foo)`)。
# 最内側から 1 個ずつ置き換え、中身を足し終えたら次の周回でその中身も同じく置き換える
# (中身に入れ子のバックティック `$(echo `x`)` が残るため)。周回の上限は、置換の目印が
# 周回ごとに減らない入力を想定外として止めるためのもの。
subst_inners=""
subst_rounds=0
while :; do
  ((++subst_rounds > 32)) && block "コマンド置換の入れ子が深すぎるため判定できません。コマンドを分けてください"
  before="$command"
  while [[ "$command" =~ \$\(([^()]*)\) || "$command" =~ \`([^\`]*)\` ]]; do
    full="${BASH_REMATCH[0]}"
    inner="${BASH_REMATCH[1]}"
    replacement=$(resolve_cmd_subst "$inner")
    subst_inners+=$'\n'"$inner"
    prefix="${command%%"$full"*}"
    suffix="${command#*"$full"}"
    command="${prefix}${replacement}${suffix}"
  done
  command+="$subst_inners"
  subst_inners=""
  [[ "$command" == "$before" ]] && break
done

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

# 透過的な実行ラッパー: 実行対象がラッパーの先にあり、内側のバイナリがそのまま
# exec される。読み飛ばして「実際に実行されるバイナリ」を解決する。shell の -c や
# eval も含む（bash -c "cmd" / eval cmd は引数以降が実行対象なので内側まで辿れる）。
# `!` と予約語 (if/then/while/do 等)、bash の coproc、zsh の noglob / nocorrect はその直後の語が
# 実行対象になるので同じく読み飛ばす。
transparent='command|builtin|exec|eval|env|nohup|nice|setsid|stdbuf|time|timeout|bash|sh|zsh|dash|ksh|mksh|ash|fish|csh|tcsh|!|if|then|elif|else|do|while|until|coproc|noglob|nocorrect'

# 引数注入ラッパー: 実行対象の引数を stdin/置換で後から与えるため、見かけ上
# 「引数なし install」でも実際にはパッケージ名が注入され得る。これらの先に PM 名が
# 現れたら復元例外なしでブロックする（echo x | xargs npm install 等）。
arginjector='xargs|find|parallel'

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

# リダイレクトは先の 1 語ごと消す。`<>` で分割すると先の後ろの語
# （`pnpm install >x foo` の foo）が別セグメントへ追い出され、判定から漏れるため。
# 先がコマンド置換でも (`cat <$(npx foo)`)、その中身は上で別の行として足してある。
# 演算子の直前の `{name}` (bash / zsh の fd 変数リダイレクト `{fd}>x`) も演算子の一部として消す。
fdvar_re='(\{[a-z_][a-z0-9_]*\})?'
redir_re="${fdvar_re}"'(&>>|&>|>>|>[|]|>&|<&|<<-|<<|<>|>|<)[[:blank:]]*[^[:blank:];&|()<>]+'
if [[ "$command" == *[\<\>]* ]]; then
  command=$(printf '%s' "$command" | sed -E "s/${redir_re}/ /g")
fi

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

  # xargs / find 経由は引数注入で「素の install」も危険なため、PM 名が現れた
  # 時点でブロックする（復元例外を与えない）。find は -exec 系より前を見ないのは、検索の
  # 起点 (`find ~/Library/pnpm`) や -name の値に PM 名が入る形で誤検知するため。
  if [[ "$bin" =~ ^($arginjector)$ ]]; then
    in_exec=1
    [[ "$bin" == find ]] && in_exec=0
    for ((j = BIN_IDX + 1; j < n; j++)); do
      strip_token "${toks[j]}"
      if [[ $in_exec -eq 0 ]]; then
        [[ "$STRIPPED" =~ ^-(exec|execdir|ok|okdir)$ ]] && in_exec=1
        continue
      fi
      cand="${STRIPPED##*/}"
      case "$cand" in
        npm|npx|pnpm|yarn|bun|bunx|pip|pip3|pipx|uv|uvx|poetry|cargo|gem|bundle|bundler)
          block "xargs/find 経由のパッケージマネージャ実行（${cand}）は禁止されています。パッケージ操作はユーザーに依頼してください"
          ;;
      esac
    done
    continue
  fi

  case "$bin" in
    npx)
      block "npx は禁止されています。代わりに pnpm dlx を使ってください"
      ;;
    bunx)
      block "bunx は実行時にパッケージを取得し得るため禁止されています"
      ;;
    uvx)
      block "uvx は実行時にパッケージを取得するため禁止されています"
      ;;
    npm)
      # npm は pnpm への一本化のため全サブコマンドを常にブロックする
      # (install / ci / run / test / exec / init すべて対象)。
      # 意図: lockfile drift 回避と pnpm 統一。npm 必須の緊急ケースは
      # ユーザーに依頼するか、shell 直下で `command npm` (fish の function を回避) で叩く。
      block "npm は禁止されています。pnpm を使ってください (install→pnpm install, run→pnpm run, exec→pnpm exec, dlx→pnpm dlx)"
      ;;
    pnpm)
      # lockfile を書き換えない復元フラグだけを除いてから「素の形」判定に渡す。
      # 値を取るフラグを入れず完全一致で比べるのは、`--frozen-lockfile=false` や
      # フラグの値の位置に置かれた package 名まで読み飛ばさないため。
      kept=()
      for t in "${rest[@]}"; do
        [[ "$t" =~ ^(--frozen-lockfile|--offline|--prefer-offline|--ignore-scripts)$ ]] || kept+=("$t")
      done
      pm_should_block 'add|dlx|create' 'install|i|install-test|it' "${kept[@]}" \
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
    cargo)
      # cargo build/test/check/fmt/clippy/fetch は許可、依存追加・バイナリ取得はブロック
      pm_should_block 'add|install' '' "${rest[@]}" \
        && block "cargo add / cargo install は禁止されています。パッケージの追加はユーザーに依頼してください"
      ;;
    go)
      # go build/test/vet/run と go mod download/verify は許可。
      # go get / go install は依存追加・バイナリ取得のためブロック。
      pm_should_block 'get|install' '' "${rest[@]}" \
        && block "go get / go install は禁止されています。パッケージの追加はユーザーに依頼してください"
      # go mod tidy は依存追加を伴い得るためブロック（download / verify / graph は許可）
      if [[ ${#rest[@]} -ge 2 ]]; then
        strip_token "${rest[0]}"
        _gosub1="$STRIPPED"
        strip_token "${rest[1]}"
        _gosub2="$STRIPPED"
        if [[ "$_gosub1" == mod && "$_gosub2" == tidy ]]; then
          block "go mod tidy は依存追加を伴い得るため禁止されています。必要なときはユーザーに依頼してください"
        fi
      fi
      ;;
    gem)
      pm_should_block 'install' '' "${rest[@]}" \
        && block "gem install は禁止されています。パッケージの追加はユーザーに依頼してください"
      ;;
    bundle|bundler)
      # bundle install / bundle exec は許可（ロックファイル復元・実行）
      pm_should_block 'add' '' "${rest[@]}" \
        && block "bundle add は禁止されています。パッケージの追加はユーザーに依頼してください"
      ;;
  esac
done <<< "$segments"

exit 0
