#!/usr/bin/env bash
#
# PreToolUse hook (Claude Code / Codex CLI 共通): 危険な Bash コマンドをブロックする
# exit 0 = 許可, exit 2 = ブロック (stderr がエージェントにフィードバックされる)
# 正本: agents/hooks/block-dangerous-commands.sh
# (claude/hooks/ と codex/hooks/ からは相対 symlink で参照される)
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
# 危険コマンド名（rm / git / chmod / sudo）にも codex 文字列と同じ gap を許容する
# （クォート分割・バックスラッシュ挿入による回避対策。本判定は正規化後に検出する）。
input_lower=$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')
gap='([\\"'"'"']|\\\\|\\")*'
if ! printf '%s' "$input_lower" \
    | grep -qE "r${gap}m|g${gap}i${gap}t|c${gap}h${gap}m${gap}o${gap}d|s${gap}u${gap}d${gap}o|c${gap}o${gap}d${gap}e${gap}x|\\\$|\`"; then
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

# 単純代入 var=value を「コマンド中の $var / ${var}」へ静的展開する。引数で渡した
# 変数名の現在値を読み、展開済み値を同じ変数に書き戻す（bash 3.2: ${!1} の indirect
# expand + printf -v で nameref を代用）。代入連鎖（p=~; q=$p; rm -rf $q のような
# 多段参照）を解決するため収束まで最大 8 回反復する。1 パスだと val が最初の抽出
# 時点の $p のまま保存され $q 置換で展開済み値に解決されないため反復が必須。
# command 側と command_for_tilde 側で同じロジックを使うため関数化している（後者は
# シングルクォート内 ~ をリテラル保持する事情で別途抽出が必要 → 代入展開以外の
# 部分は本関数では扱わず、呼び出し前に view を作っておく）。
expand_assignments() {
  local _var=$1 _prev _iter=0 _cur=${!1} assignments asgn name val esc_name esc_val
  while [[ $_iter -lt 8 ]]; do
    _prev=$_cur
    _iter=$((_iter + 1))
    assignments=$(printf '%s' "$_cur" \
      | grep -oE '(^|[[:space:];&|])[A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*' \
      | sed -E 's/^[[:space:];&|]+//')
    [[ -z "$assignments" ]] && break
    while IFS= read -r asgn; do
      [[ -z "$asgn" ]] && continue
      name="${asgn%%=*}"
      val="${asgn#*=}"
      esc_name=$(printf '%s' "$name" | sed 's/[][\\.*^$/]/\\&/g')
      esc_val=$(printf '%s' "$val" | sed 's/[\\&/]/\\&/g')
      _cur=$(printf '%s' "$_cur" | sed -E \
        -e "s/\\\$\\{${esc_name}\\}/${esc_val}/g" \
        -e "s/\\\$${esc_name}([^A-Za-z0-9_]|\$)/${esc_val}\\1/g")
    done <<< "$assignments"
    [[ "$_cur" = "$_prev" ]] && break
  done
  printf -v "$_var" '%s' "$_cur"
}

# ANSI-C クォート $'...' は実行時にエスケープシーケンスをデコードする（例: $'\056'→.、
# $'\x2e'→.）。8進・16進・制御文字を静的に追うのは非現実的なため、エスケープ（\）を
# 内包する $'...' は安全側で全面ブロックする。エスケープを含まない $'...' は後段の
# クォート除去で解決する。通常のクォート文字列で代替できる。
if printf '%s' "$command" | grep -qE "\\\$'[^']*\\\\"; then
  echo "ブロック: ANSI-C クォート（\$'...'）内のエスケープシーケンスは安全側で禁止されています" >&2
  exit 2
fi

# シェル意味論に従ってコマンドを正規化する（.co""dex / .co\dex / $d=.codex; ...
# のような回避を解消するため、guard-pkg-install.sh と同じ方針）。
# 段階1: 1 つの sed -E で以下をまとめて処理する:
#   - ANSI-C $'...' / locale $"..." quote 除去
#   - \X → X（バックスラッシュエスケープ解除）
#   - ${IFS} / $IFS の空白化（bash${IFS}-c のような区切り回避対策。
#     ${IFS:0:1} 等のサブ展開や波括弧なし $IFS も含む）
# この時点の view を command_pre_sq として保存し、eval / *sh -c 判定と再パース判定で
# 使う（シングルクォート除去前の view が必要なため。bash -c '$(...)' のように
# eval / *sh -c の引数では、シングルクォート内の $() も再パース時に展開されて実行される）。
command=$(printf '%s' "$command" | sed -E \
  -e "s/\\\$'([^']*)'/\1/g" \
  -e "s/\\\$\"([^\"]*)\"/\1/g" \
  -e 's/\\(.)/\1/g' \
  -e 's/\$\{IFS[^}]*\}/ /g' \
  -e 's/\$IFS([^A-Za-z0-9_]|$)/ \1/g')

command_pre_sq=$command

# 段階2: シングルクォート '...' の処理（通常コマンド用、bash の quote removal を再現）:
#   - 中身に $ または ` を含む場合: 動的展開リテラル（bash は展開しない）として
#     空白に置換し、後段の判定経路に流さない。
#     例: printf %s '$(git reset --hard)' → printf %s   （無害な文字列出力）
#   - 含まない場合: quote のみ削除して中身を保持。
#     例: 'git' reset --hard → git reset --hard、rm -rf '/' → rm -rf /、
#         touch '.codex/config.toml' → touch .codex/config.toml
# 段階3: ダブルクォート " を全削除（ダブルクォート内は $ が展開されるため中身保持）
# ANSI-C クォート $'...'（エスケープなし）と locale 翻訳クォート $"..."（中身は実行時に
# 通常の二重引用符相当のトークン）もクォート除去して中身を連結する。$"..." 内の \ は
# 通常の二重引用符と同じ限定的なエスケープ規則で、$'\056' のような実行時デコードを起こさない
# ため安全側ブロックは不要。エスケープ内包の $'...' は上で安全側ブロック済み。
# .codex 検出にのみ使う。サブシェルでの正規化結果を $command に上書きする。
command=$(printf '%s' "$command" | sed -E \
  -e "s/'[^']*[\$\`][^']*'/ /g" \
  -e "s/'([^']*)'/\1/g" \
  -e 's/"//g')

# コマンド置換 $(...) / `...` の中身は位置に関係なくシェルが実行する（コマンド名
# 位置でも引数位置でも、$(...) は常に評価される）。これを外側に "; 中身" として
# 追加した view を構築し、後段の本判定が中身の危険コマンドを直接検出できるように
# する。echo $(git reset --hard) や : $(rm -rf /) のような「引数位置の動的実行」を捕捉。
#
# パラメータ展開 ${VAR:-default} は default 値が引数位置では word splitting されて
# 引数として渡されるだけで実行されない（echo ${msg:-sudo required} の sudo は echo
# の引数で sudo 実行ではない）。コマンド名位置に置かれた場合のみ実行されるが、
# その場合は別経路の「コマンド名トークン動的展開」判定が ${cmd:-git reset --hard}
# や ${x:-rm -rf /} を捕捉するため、ここで外側展開する必要はない（引数位置の
# 誤検知を生むため）。
#
# シングルクォート '...' 内は前段の正規化で空白化済み（中身に $ / ` を含む場合）か、
# quote 除去済み（含まない場合）のため、ここでの抽出時には quote semantic が
# 正しく反映されている。printf %s '$(git reset --hard)' のような無害な文字列出力は
# 既に空白化されており抽出されない。
nested=$(
  printf '%s' "$command" | grep -oE '\$\([^)]*\)' | sed -E -e 's/^\$\(//' -e 's/\)$//'
  printf '%s' "$command" | grep -oE '`[^`]*`' | sed -E -e 's/^`//' -e 's/`$//'
)
if [[ -n "$nested" ]]; then
  command="$command; $(printf '%s' "$nested" | tr '\n' ';')"
fi

# コマンド名トークン（セグメント先頭の代入語群 NAME=value をスキップした後の、
# 最初の空白までのトークン）に動的展開（$(...) / `...` / ${...} / $VAR）が含まれる
# 場合、危険コマンド名（rm / git / sudo / chmod 他）の動的構築による検出回避を
# 完全に塞ぐため、後続を問わず安全側でブロックする。具体的に防ぐ攻撃:
#   - 分割生成: $(printf %s g it) reset --hard、$(printf g; printf it) reset --hard
#   - 隣接連結: ${x:-g}${y:-it} reset --hard、$(printf g)$(printf it) reset --hard
#   - 先頭リテラル+動的展開連結: g$(printf it) reset --hard、su$(printf do) whoami
#   - 任意引数の動的構築 sudo: ${x:-su}${y:-do} whoami（後続が任意のため reset/--force 等を要求しない）
#   - long option 形 rm: $(printf %s r m) --recursive --force / 等（後続のフラグ列も問わない）
#   - default 値に引数まで含む形: ${cmd:-git reset --hard} / ${x:-rm -rf /}
# 代入語スキップ: FOO=$(pwd) env / PY=${PYTHON:-python3} script.py / A=1 B=2 cmd の
# ような環境変数代入が先頭にある形では、代入語をスキップしてから最初の非代入語を
# コマンド名として評価する。代入語の value 部に動的展開を持つ場合（FOO=$(rm -rf /)）は、
# 外側展開フェーズが内側コマンドを別経路で本判定に流す。
# 引数位置の動的展開（echo $(date)、ls $(pwd)/subdir、wc -l ${LOGFILE:-default.log} 等）は
# コマンド名トークンが静的なので対象外で誤検知を抑える。
# 注: この判定は literal 化フェーズの前に動かす必要がある。literal 化は ${x:-git reset --hard}
# のような形を「git」literal に潰してしまい引数 reset --hard を失わせるが、この判定は
# 展開全体を 1 つの動的構築トークンとして検出する。
# AI エージェントは動的構築コマンド名を書かず、静的リテラルで書くこと（AGENTS.md 参照）。
# $(brew --prefix)/bin/cmd や ${PYTHON:-python3} script.py 等の動的パス起動は副作用として
# ブロックされるが、静的パス（/opt/homebrew/bin/cmd や python3）で代替可能。
if printf '%s' "$command" | grep -qE '(^|[;&|({])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=([^[:space:];&|]|\$\([^)]*\)|`[^`]*`|\$\{[^}]*\}|\$[a-zA-Z_][a-zA-Z0-9_]*)*[[:space:]]+)*((env|command|nice|exec|nohup|setsid|stdbuf|timeout|ionice|chrt|time)([[:space:]]+([-+][^[:space:]]+([[:space:]]+[^-+<[:space:];&|][^[:space:];&|]*)?|[0-9][^[:space:];&|]*|[A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*))*[[:space:]]+)*([^[:space:];&|]*/)?([^[:space:];&|()`{}<>$=]|\$\([^)]*\)|`[^`]*`|\$\{[^}]*\}|\$[a-zA-Z_][a-zA-Z0-9_]*)*(\$\([^)]*\)|`[^`]*`|\$\{[^}]*\}|\$[a-zA-Z_][a-zA-Z0-9_]*)([^[:space:];&|()`{}<>$=]|\$\([^)]*\)|`[^`]*`|\$\{[^}]*\}|\$[a-zA-Z_][a-zA-Z0-9_]*)*([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: コマンド名トークンに動的展開を含むコマンドは安全側で禁止されています（危険コマンド名の動的構築対策）。コマンド名は静的リテラルで書いてください。" >&2
  exit 2
fi

# eval / *sh -c (bash -c / zsh -c / dash -c / sh -c / fish -c / ksh -c / tcsh -c 等)
# は引数を別のシェル文として再実行するため、引数に動的展開を含む場合は危険コマンド名
# 構築の経路となる（eval g$(printf it) reset --hard、bash -c "$(printf g)$(printf it)
# reset --hard" 等）。トップレベルの「コマンド名トークン動的展開」判定はこれらの引数の
# 中の動的展開を見ないため、別経路として安全側で全面ブロックする。
# 単語境界 (^|[^A-Za-z0-9_]) で判定するため、以下のラッパー・前置形にも対応する:
#   - 絶対パス起動: /bin/bash -c "..."、/usr/local/bin/zsh -c "..."
#   - 環境変数代入: FOO=1 bash -c "..."、A=1 B=2 bash -c "..."
#   - 透過ラッパー: env bash -c "..."、env -i sh -c "..."、command bash -c "..."、
#     nice eval ...
# shell 名と -c の間にオプションフラグや値トークンが挟まる形にも対応する:
#   - 値を取らないフラグ: bash --noprofile -c "..."、bash -l -c "..."、sh -i -c "..."
#   - 値を取るフラグ + 値: bash -o posix -c "..."、bash -O extglob -c "..."、
#                         bash +O extglob -c "..."、bash --rcfile X -c "..."、
#                         bash --init-file X -c "..."
#   - 複合: bash -o posix --norc -c "..."、bash -o posix -l -c "..."
# 許容トークン（順序が重要、値を取るフラグ + 値 → 値なし長/短フラグ → < の順）:
#   - [-+][oO][[:space:]]+VALUE : -o/-O/+o/+O フラグ + 値
#   - (--rcfile|--init-file)[[:space:]]+VALUE : 値を取る長フラグ + 値
#   - --[a-zA-Z][a-zA-Z-]* : 値を取らない長フラグ（--noprofile / --norc / --posix 等）
#   - [-+][^-[:space:]][^[:space:]]* : 値を取らない短フラグ（-i / -l / -x 等）
#   - < : input redirection
# 任意の非フラグトークン（script.sh 等）と -- 単独はループのどの選択肢にもマッチしないため
# ループが停止する。これにより以下が正しく扱われる:
#   - bash script.sh -c '...' : script.sh で止まり、-c が script の引数として通過
#   - bash -- -c '...' : -- で止まり、-c が script 名/引数として通過（bash の semantic 通り）
#   - bash -- script.sh -c '...' : -- で止まり、以降は script 引数として通過
# shell 名は [a-zA-Z]*sh|nu の正規表現で bash/zsh/dash/sh/fish/tcsh/ksh/mksh/ash/yash/
# posh/nushell 等を網羅する（* で 0 文字以上にして sh 単独もマッチさせる）。
# eval / *sh -c の素のリテラル使用（eval ls -la、bash -c "echo hello"）や、引数が
# literal 化済みの場合（bash -c sudo whoami 等）は通過する。
# この判定は literal 化フェーズの前に動かす必要がある（literal 化で eval の引数中の
# 動的展開が潰されるため）。
# 判定A: シングルクォート除去後の command を入力にし、ダブルクォート内動的展開や
# 引数位置の動的展開を捕捉する。bash -c "$(date)" / bash -c $(date) / bash -c $VAR 等。
# 注意: シングルクォート内動的展開（bash -c '$(date)'）は段階2 の sq semantic 処理で
# `$` 含むシングルクォートが空白置換されているため判定A では捕捉できない。判定B でカバー。
#
# トップレベル判定の前置: セグメント先頭から「代入語 NAME=val」「透過ラッパー env/command/
# nice/exec/nohup/setsid/stdbuf/timeout/ionice/chrt + そのオプション」「絶対パス」を順次
# 消費した位置に *sh / eval が来る形のみマッチ。これにより echo "foo bash -c $(date)"
# のような echo の引数内 bash -c 文字列（ダブルクォート除去後の literal）は echo が
# shell 名でないため通過する。
if printf '%s' "$command" | grep -qiE '(^|[;&|({])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*[[:space:]]+)*((env|command|nice|exec|nohup|setsid|stdbuf|timeout|ionice|chrt|time)([[:space:]]+([-+][^[:space:]]+([[:space:]]+[^-+<[:space:];&|][^[:space:];&|]*)?|[0-9][^[:space:];&|]*|[A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*))*[[:space:]]+)*([^[:space:];&|]*/)?(eval|([a-zA-Z]*sh|nu)([[:space:]]+([-+][oO][[:space:]]+[^-+<[:space:];&|][^[:space:];&|]*|(--rcfile|--init-file)[[:space:]]+[^[:space:]]+|--[a-zA-Z][a-zA-Z-]*|[-+][^-[:space:]][^[:space:]]*|<))*[[:space:]]+(-[a-z]*c[a-z]*|--command))[[:space:]]+[^;&|]*(\$\(|`|\$[a-zA-Z_{])'; then
  echo "ブロック: eval / *sh -c の引数に動的展開を含むコマンドは安全側で禁止されています（危険コマンド名構築対策）。引数を静的リテラルで書いてください。" >&2
  exit 2
fi

# 判定B: シングルクォート除去前の command_pre_sq を入力にし、トップレベルの *sh -c の
# 直後がシングルクォートで囲まれていて、その中に動的展開が含まれる形だけを捕捉する。
# bash -c '$(date)' / bash -c '${x:-rm -rf /}' / eval 'g$(printf it) reset --hard' 等。
# -c の直後にシングルクォート ' を必須にすることで、echo 'foo bash -c $(date)' のような
# echo の引数内に bash -c が文字列として現れるケース（シングルクォート内 literal）の
# 誤検知を防ぐ（echo の引数のシングルクォートは bash -c の直後ではない）。
# トップレベル判定の前置は判定A と同じ（代入語 / ラッパー / 絶対パスを消費後に shell 名）。
if printf '%s' "$command_pre_sq" | grep -qiE "(^|[;&|({])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*[[:space:]]+)*((env|command|nice|exec|nohup|setsid|stdbuf|timeout|ionice|chrt|time)([[:space:]]+([-+][^[:space:]]+([[:space:]]+[^-+<[:space:];&|][^[:space:];&|]*)?|[0-9][^[:space:];&|]*|[A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*))*[[:space:]]+)*([^[:space:];&|]*/)?(eval|([a-zA-Z]*sh|nu)([[:space:]]+([-+][oO][[:space:]]+[^-+<[:space:];&|][^[:space:];&|]*|(--rcfile|--init-file)[[:space:]]+[^[:space:]]+|--[a-zA-Z][a-zA-Z-]*|[-+][^-[:space:]][^[:space:]]*|<))*[[:space:]]+(-[a-z]*c[a-z]*|--command))[[:space:]]+'[^']*(\\\$\\(|\`|\\\$[a-zA-Z_{])"; then
  echo "ブロック: eval / *sh -c の引数（シングルクォート内）に動的展開を含むコマンドは安全側で禁止されています（危険コマンド名構築対策）。引数を静的リテラルで書いてください。" >&2
  exit 2
fi

# *sh への here-string (<<<) / process substitution (<(...)) / pipe 経由のコード渡し、
# source / . によるコード読み込みも再パース経路となる。これらの「再パース対象」自身に
# 動的展開残留が含まれる場合のみ安全側でブロックする。コマンド全体に動的展開があっても
# 再パース対象に含まれない場合（別セグメントの $(date) 等）は誤検知しない。
# 各経路と判定対象範囲:
#   (1) *sh ... (<<<|<\() X : here-string / process subst の X が判定対象
#   (2) X | *sh             : pipe の左側 X が判定対象（同セグメント内）
#   (3) source/. <\( X \)   : process subst の中身 X が判定対象
# 例 (block):
#   - bash <<< "$(printf g)$(printf it) reset --hard"   ← (1) <<< 直後に動的展開
#   - printf %s '$(...)' | bash                          ← (2) パイプ左側に動的展開
#   - source <(printf %s '$(...)')                       ← (3) <(...) 内に動的展開
# 例 (allow):
#   - bash <<< 'echo hello'; echo $(date)                ← セグメント外の動的展開は無関係
#   - bash <(printf %s 'echo hello'); echo $(date)
#   - bash <<< 'echo hello' / source ~/.bashrc          ← 再パース対象に動的展開なし
# *sh の後ろにオプションフラグ・値・input redirection (<) が挟まる形にも対応する:
#   - bash -s <<<、bash --noprofile <<<、bash < <(...)、bash -s < <(...)
#   - bash -o posix <<<、bash -O extglob <<<、bash +O extglob <<<
#   - bash --rcfile X <<<、bash -o posix < <(...)
# 許容トークンは -c 判定と同じ（値を取るフラグ + 値 → 値なしフラグ → < の順）。
# 過検知のトレードオフ: curl URL | bash 等は動的展開がないため通過する（実害ありの
# パターンだが静的に追えない経路。AGENTS.md で別途警告）。
if printf '%s' "$command_pre_sq" | grep -qiE '(^|[;&|({])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*[[:space:]]+)*((env|command|nice|exec|nohup|setsid|stdbuf|timeout|ionice|chrt|time)([[:space:]]+([-+][^[:space:]]+([[:space:]]+[^-+<[:space:];&|][^[:space:];&|]*)?|[0-9][^[:space:];&|]*|[A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*))*[[:space:]]+)*([^[:space:];&|]*/)?([a-zA-Z]*sh|nu)([[:space:]]+([-+][oO][[:space:]]+[^-+<[:space:];&|][^[:space:];&|]*|(--rcfile|--init-file)[[:space:]]+[^[:space:]]+|--[a-zA-Z][a-zA-Z-]*|[-+][^-[:space:]][^[:space:]]*|<))*[[:space:]]*(<<<|<\()[^;&|]*(\$\(|`|\$[a-zA-Z_{])|(^|[;&])[^;&]*(\$\(|`|\$[a-zA-Z_{])[^;&]*\|[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*[[:space:]]+)*((env|command|nice|exec|nohup|setsid|stdbuf|timeout|ionice|chrt|time)([[:space:]]+([-+][^[:space:]]+([[:space:]]+[^-+<[:space:];&|][^[:space:];&|]*)?|[0-9][^[:space:];&|]*|[A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*))*[[:space:]]+)*([^[:space:];&|]*/)?([a-zA-Z]*sh|nu)([[:space:]]|$|[;&|])|(^|[;&|({])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*[[:space:]]+)*((env|command|nice|exec|nohup|setsid|stdbuf|timeout|ionice|chrt|time)([[:space:]]+([-+][^[:space:]]+([[:space:]]+[^-+<[:space:];&|][^[:space:];&|]*)?|[0-9][^[:space:];&|]*|[A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*))*[[:space:]]+)*([^[:space:];&|]*/)?(source|\.)[[:space:]]+<\([^)]*(\$\(|`|\$[a-zA-Z_{])'; then
  echo "ブロック: シェル再パース経路（here-string / pipe / process substitution / source）の対象に動的展開を含むコマンドは安全側で禁止されています（危険コマンド名構築対策）。再パース対象は静的リテラルで書いてください。" >&2
  exit 2
fi

# コマンド置換 $(...) / `...` の中身に危険コマンド名（rm / git / sudo / chmod）の
# トークンが含まれる場合、その置換式全体を該当コマンド名 literal に置き換える
# （guard-pkg-install.sh と同じ流儀）。例: $(printf git) reset --hard → git reset --hard、
# `which rm` -rf / → rm -rf /。中身に危険コマンド名を含まない $(...) / `...` は残留し、
# 後段の動的展開残留判定（.codex 参照 / 書き込み系コマンド / 書き込みリダイレクト）が拾う。
# 中身は case-insensitive 比較（I フラグ）: macOS は case-insensitive FS で大文字
# バイナリ（$(printf GIT) 等）も解決されるため。\1 には元のテキスト（大文字含む）が
# 残るが、後段の本判定が -i 付きで捕捉する。
command=$(printf '%s' "$command" | sed -E \
  -e 's/\$\([^)]*[^A-Za-z0-9_](rm|git|sudo|chmod)[^A-Za-z0-9_)][^)]*\)/\1/Ig' \
  -e 's/\$\([^)]*[^A-Za-z0-9_](rm|git|sudo|chmod)\)/\1/Ig' \
  -e 's/\$\((rm|git|sudo|chmod)[^A-Za-z0-9_)][^)]*\)/\1/Ig' \
  -e 's/\$\((rm|git|sudo|chmod)\)/\1/Ig' \
  -e 's/`[^`]*[^A-Za-z0-9_](rm|git|sudo|chmod)[^A-Za-z0-9_`][^`]*`/\1/Ig' \
  -e 's/`[^`]*[^A-Za-z0-9_](rm|git|sudo|chmod)`/\1/Ig' \
  -e 's/`(rm|git|sudo|chmod)[^A-Za-z0-9_`][^`]*`/\1/Ig' \
  -e 's/`(rm|git|sudo|chmod)`/\1/Ig')

# パラメータ展開 ${VAR:-default} / ${VAR-default} / ${VAR:=default} / ${VAR:+alt} 等の
# 中身に危険コマンド名トークンが含まれる場合、その展開全体を該当コマンド名 literal に
# 置き換える（コマンド置換と同じ流儀、case-insensitive）。例: ${x:-git} reset --hard
# → git reset --hard、${UNSET:-rm} -rf / → rm -rf /。x が未設定/null なら bash は
# default 値を採用するため、検出側でも default 値の literal を判定経路に流す。
# 中身に危険コマンド名を含まない ${...}（${USER} / ${#PATH} / ${PWD:0:10} 等）は
# 残留し、後段の動的展開残留判定が拾う。
command=$(printf '%s' "$command" | sed -E \
  -e 's/\$\{[^}]*[^A-Za-z0-9_](rm|git|sudo|chmod)[^A-Za-z0-9_}][^}]*\}/\1/Ig' \
  -e 's/\$\{[^}]*[^A-Za-z0-9_](rm|git|sudo|chmod)\}/\1/Ig' \
  -e 's/\$\{(rm|git|sudo|chmod)[^A-Za-z0-9_}][^}]*\}/\1/Ig' \
  -e 's/\$\{(rm|git|sudo|chmod)\}/\1/Ig')

# 単純な変数代入 `var=value` を「コマンド中の $var / ${var}」に静的展開する。
# 例: d=.codex; touch $d/foo → touch .codex/foo、
# 　　 a=.co; b=dex; touch $a$b/foo → touch .codex/foo（連結も解決される）。
# 代入連鎖（p=~; q=$p; ...）も expand_assignments の収束反復で解決される。
# bash の通常代入と異なるケース（export FOO=bar / function ローカル等）は対象外。
# command_for_tilde 側の代入展開は tilde 判定の遅延生成と一緒に段階11 で行う。
expand_assignments command

# 動的展開（コマンド置換・バックティック・未追跡変数）が残っていて、かつ
# .codex 文字列を含むコマンドは、展開後に .codex 配下を触る可能性があるため
# 安全側で全面ブロックする。Cymulate notify エスケープは静的解析では追えない
# 構築（touch $(pwd)/.codex/... 等）でも成立するため。
# ただし以下は .codex を構築する経路として実害が少ない/合法経路のため除外する:
#   - $HOME / ${HOME} / ~: ホーム配下の .codex は後段の token 走査が許可する
#   - $TMPDIR / ${TMPDIR}: /tmp や /var/folders/... を指し、cwd 外のため
#     .codex 構築されても Cymulate notify エスケープは成立しない
#   - $XDG_* / ${XDG_*}: 同様に cwd 外の XDG ベースディレクトリ
# 入力は混在の可能性があるため大小無視（BSD sed の I フラグ）で除外する。
residual=$(printf '%s' "$command" | sed -E \
  -e 's/\$\{home\}//Ig' \
  -e 's/\$home([^A-Za-z0-9_]|$)/\1/Ig' \
  -e 's/\$\{tmpdir\}//Ig' \
  -e 's/\$tmpdir([^A-Za-z0-9_]|$)/\1/Ig' \
  -e 's/\$\{xdg_[a-z_]+\}//Ig' \
  -e 's/\$xdg_[a-z_]+([^A-Za-z0-9_]|$)/\1/Ig')
# 動的展開残留（$(...)、`...`、$VAR、${VAR}）が $residual に存在するかを 1 度だけ評価し、
# 以降の 3 つの判定（.codex / 書き込み系コマンド / 書き込みリダイレクト）で再利用する。
# 過去は各 if で同じ grep を独立に走らせていたが、2 プロセス起動分の冗長性を削減。
has_dynamic=0
if printf '%s' "$residual" | grep -qE '\$\(|`|\$[a-zA-Z_{]'; then
  has_dynamic=1
fi

if [[ "$has_dynamic" = 1 ]] && printf '%s' "$residual" | grep -qi '\.codex'; then
  echo "ブロック: 動的展開を含む .codex/ 参照は安全側で禁止されています（Cymulate notify エスケープ対策）" >&2
  exit 2
fi

# 動的展開がファイル書き込み・ディレクトリ操作系コマンドの引数に現れる場合、
# その中身が `.codex` を構築する可能性があるため安全側でブロックする。
# 例: touch .$(printf codex)/config.toml → 静的に .codex 検出できないが、
# 実行時に .codex/config.toml になる。$HOME / ${HOME} / ~ は上で除外済み。
# printf / echo は単体ではファイルへ書けないため対象外（リダイレクト併用は後段の
# リダイレクト判定が拾う）。動的展開 + printf の日常頻出組を誤ブロックしないため。
write_cmds='touch|mkdir|install|cp|mv|dd|tee|ln'
if [[ "$has_dynamic" = 1 ]] && printf '%s' "$residual" | grep -qiE "(^|[;&|({\`[:space:]])($write_cmds)([[:space:]]|[;&|)}\`]|$)"; then
  echo "ブロック: 動的展開を含む書き込み系コマンドは安全側で禁止されています（.codex 構築の可能性、Cymulate notify エスケープ対策）" >&2
  exit 2
fi

# 動的展開と書き込み系リダイレクト演算子の組み合わせも同様に安全側ブロックする。
# 例: echo x > .$(echo codex)/config.toml → 実行時に .codex/config.toml へ書き込み。
# 対象演算子: > / >> / >| / &> / &>> / N> / N>> （N は fd 番号）
# 入力リダイレクト < / << / <<< と fd コピー >& は対象外（書き込み先がファイルでない）。
if [[ "$has_dynamic" = 1 ]] && printf '%s' "$residual" | grep -qE '(^|[^&0-9])>[>|]?[^&]|&>>?[^&]|[0-9]+>>?[^&]'; then
  echo "ブロック: 動的展開を含む書き込み系リダイレクトは安全側で禁止されています（.codex 構築の可能性、Cymulate notify エスケープ対策）" >&2
  exit 2
fi

# --- 破壊的ファイル操作 ---
# 大文字・大小混在表記（RM / Git 等、macOS は case-insensitive FS でバイナリ解決される）も検出するため本判定は -i を付ける。
# 絶対パス起動（/bin/rm / /opt/homebrew/bin/git 等）も検出するため、本判定の先行文字クラスに / を含める
# （バックスラッシュ起動 \rm 等は正規化フェーズの \X→X で素の rm に解決されるが、先行クラスにも \ を加えて二重に保護する）。
rm_rf_pattern='(^|[;&|({`[:space:]/\])rm[[:space:]]+('
rm_rf_pattern+='([^;&|]*[[:space:]])?-[a-zA-Z]*[rR][a-zA-Z]*f[a-zA-Z]*'
rm_rf_pattern+='|([^;&|]*[[:space:]])?-[a-zA-Z]*f[a-zA-Z]*[rR][a-zA-Z]*'
rm_rf_pattern+='|([^;&|]*[[:space:]])?(--recursive|-[a-zA-Z]*[rR][a-zA-Z]*)[^;&|]*(--force|[[:space:]]-[a-zA-Z]*f[a-zA-Z]*)'
rm_rf_pattern+='|([^;&|]*[[:space:]])?(--force|-[a-zA-Z]*f[a-zA-Z]*)[^;&|]*(--recursive|[[:space:]]-[a-zA-Z]*[rR][a-zA-Z]*)'
rm_rf_pattern+=')'
if printf '%s\n' "$command" | grep -qiE "$rm_rf_pattern"; then
  # tilde 判定用 view を遅延生成する。rm を含むコマンドのみ生成コストを払い、
  # git/sudo/chmod など rm 以外のコマンドに対する sed 起動を削減する。view の
  # クオート除去方針はシングル/ダブルで非対称:
  #   - シングルクォート '...': 中身に ~ も $ も含まなければ除去（'rm' -rf ~
  #     のようなコマンド名分割クオートを解消）。中身に ~ があれば保持して
  #     tilde 判定の前置 [[:space:]]+ で除外、中身に $ があれば保持して後段の
  #     代入展開（'$p' → '~'）後に同じく前置クオート文字で除外する。$ 保護を
  #     しないと p=~; rm -rf '$p' のような literal $p が rm -rf ~ 相当に
  #     見えて過ブロックする。
  #   - ダブルクォート "...": 一律削除。"~" / "$q"（変数展開経由）が静的に
  #     区別できないため過ブロックは許容（'~' で書く回避策あり）。
  # 続いて、ホーム値を返すコマンド置換 $(echo ~) / $(printf %s ~) / `printf ~`
  # 等も ~ に潰す（代入経由 p=$(printf %s ~); rm -rf $p でホーム破壊が起きる
  # ため）。echo/printf 限定なのは $(rm -rf ~) のような「中身に危険コマンドを
  # 含む置換」を潰すと中身の rm を tilde 判定で見られなくなるため。
  # 「裸 ~」の判定は ~ の直前が空白（コマンド名直後 or 中身末尾の空白）であること
  # を要件にする。これで printf %s foo~ や printf %s /tmp/~ のように ~ が word
  # 中間にある（bash でも tilde 展開されない）ケースを誤検出しない。printf は
  # フォーマット引数（%s, "%s\n", -- 等）を挟んで ~ が後置される形が普通なので、
  # 任意中身 + 空白 + ~ + 任意末尾 を許容する。
  # 引用付き ~（'$(printf %s '"'"'~'"'"')' のような中身 quoted ~）は shell
  # 仕様では tilde 展開されずリテラル名扱いになる。csub 潰しの前にシングル
  # クォート内 ~ を sentinel (1 バイト 0x01) に隔離し、csub 潰し後に元に戻す
  # ことで、引用付き ~ を保護する（潰しの対象は引用なし裸 ~ に限定される）。
  # sed の g フラグは非重複マッチを順次置換するだけで '~~' のような複数 ~ を
  # 含むクオートでは 1 回の sed では 1 個しか sentinel 化できないため、シェルの
  # for ループで収束まで反復する（最大 8 回、無限ループ防止）。
  # 既知制限: 段階4 nested / 段階8 csub literal 化は command_for_tilde に未反映
  # （$(printf %s rm) -rf ~ のような動的構築 rm + 静的 tilde 組み合わせは検出
  # 外れ）。再パース経路 + 静的リテラルと併せて issue #56 で対応予定。
  _sentinel=$'\x01'
  _view=$command_pre_sq
  for _i in 1 2 3 4 5 6 7 8; do
    _new=$(printf '%s' "$_view" | sed -E "s/'([^']*)~([^']*)'/'\\1${_sentinel}\\2'/g")
    [[ "$_new" = "$_view" ]] && break
    _view=$_new
  done
  command_for_tilde=$(printf '%s' "$_view" | sed -E \
    -e "s/'([^~'\$${_sentinel}]*)'/\\1/g" \
    -e 's/"//g' \
    -e "s/\\\$\\((echo|printf)[[:space:]]+([^)]*[[:space:]])?~[^)]*\\)/~/g" \
    -e "s/\`(echo|printf)[[:space:]]+([^\`]*[[:space:]])?~[^\`]*\`/~/g" \
    -e "s/${_sentinel}/~/g")
  expand_assignments command_for_tilde

  # tilde-prefix（~ / ~+ / ~- / ~user / ~user/path）は command_for_tilde で
  # 判定し、シングルクォート tilde リテラルや 'rm' 等の分割クオートを正しく
  # 扱う。/ / $HOME / .. / ./ の既存分岐はクオート除去後の view（$command）で
  # 従来どおり判定する。|| 短絡で第二 grep は第一が未マッチ時のみ走る。
  if printf '%s\n' "$command" | grep -qiE '(^|[;&|({`[:space:]/\])rm[[:space:]].*[[:space:]]+(/|\$HOME|\.\.(/|[[:space:]]|[;&|)}`]|$)|\./?([[:space:]]|[;&|)}`]|$))' \
     || printf '%s\n' "$command_for_tilde" | grep -qiE '(^|[;&|({`[:space:]/\])rm[[:space:]].*[[:space:]]+~[^/[:space:];&|)}`]*([/[:space:];&|)}`]|$)'; then
    echo "ブロック: rm -rf で危険なパスが指定されています" >&2
    exit 2
  fi
fi

# --- Git 破壊的操作 ---
# git のグローバルオプション（-C <path> / -c <k>=<v> / --no-pager 等）をサブコマンド前に
# 挟む回避（git -C . push --force 等）に対応するため、サブコマンド前の option 列を許容する。
if printf '%s\n' "$command" | grep -qiE '(^|[;&|({`[:space:]/\])git[[:space:]]+(-[^[:space:];&|]+([[:space:]]+[^-[:space:];&|][^[:space:];&|]*)?[[:space:]]+)*push[[:space:]]+([^;&|]*[[:space:]])?(--force|--force-with-lease(=[^[:space:]]*)?|--mirror|-[a-zA-Z]*f[a-zA-Z]*|\+[^[:space:];&|]+)([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: git push --force は禁止されています" >&2
  exit 2
fi

# reset 側も同様にグローバルオプション（-C <path> / -c <k>=<v> / --flag 等）を許容する。
# reset の後にサブコマンドオプション（-q / --quiet 等）を挟む形（git reset -q --hard）にも対応する。
if printf '%s\n' "$command" | grep -qiE '(^|[;&|({`[:space:]/\])git[[:space:]]+(-[^[:space:];&|]+([[:space:]]+[^-[:space:];&|][^[:space:];&|]*)?[[:space:]]+)*reset[[:space:]]+([^;&|]*[[:space:]])?--hard([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: git reset --hard は禁止されています" >&2
  exit 2
fi

# --- .codex 読み取り専用アクセスの許可判定 ---
# .codex 保護の趣旨は「プロジェクト内 .codex/ の生成・改変の防止」（Cymulate
# notify エスケープ対策）であり、読み取りは無害。以下をすべて満たす場合のみ
# 後段の .codex 参照ブロックを免除する:
#   1. 動的展開残留がない（has_dynamic=0。動的構築の書き込みを見逃さないため）
#   2. 書き込み系リダイレクト（> >> >| &> N>）がない
#   3. 全セグメントの先頭コマンドが読み取り専用 allowlist に含まれる
#      （env/nice 等のラッパー越しは追跡せず安全側で不許可。sed は -i で
#      書き込めるため対象外。find は -delete/-exec を持つため対象外）
codex_readonly_ok=0
if [[ "$has_dynamic" = 0 ]] && printf '%s' "$command" | grep -qi '\.codex'; then
  if ! printf '%s' "$command" | grep -qE '(^|[^&0-9])>[>|]?([^&]|$)|&>>?([^&]|$)|[0-9]+>>?([^&]|$)'; then
    readonly_cmds='grep|egrep|fgrep|rg|cat|head|tail|less|more|wc|ls|stat|file|diff|cmp|md5|shasum|sha256sum|strings|hexdump|od|readlink|basename|dirname|test'
    codex_readonly_ok=1
    while IFS= read -r _seg; do
      _seg="${_seg#"${_seg%%[![:space:]]*}"}"
      [[ -z "$_seg" ]] && continue
      _first="${_seg%%[[:space:]]*}"
      _first="${_first##*/}"
      _first=$(printf '%s' "$_first" | tr '[:upper:]' '[:lower:]')
      if ! printf '%s' "$_first" | grep -qE "^($readonly_cmds)$"; then
        codex_readonly_ok=0
        break
      fi
    done <<< "$(printf '%s' "$command" | tr ';&|(){}' '\n\n\n\n\n\n\n')"
  fi
fi

# --- プロジェクト内 [.]codex ディレクトリへの参照をブロック ---
# 書き込みコマンドの列挙ではすべてのリダイレクト/エイリアスを網羅できないため、
# コマンド全体に対して相対パスの [.]codex を独立トークンとして検出する。
# 例: `> .codex/config.toml`, `install -d .codex`, `printf x > .codex/config.toml` 等
#
# macOS APFS は既定で case-insensitive のため、`.Codex` 等の表記でも
# 同一ファイルにアクセスできる。検出は大文字小文字を無視して行う。
# Codex CLI と同居するプロジェクトでは、AI が .codex/ を生成すると Codex 起動時のエスケープ経路になりうるため、Bash 経路でも防ぐ（Edit/Write 経路は対象外）。
if [[ "$codex_readonly_ok" = 0 ]] && printf '%s\n' "$command" | grep -qiE '(^|[;&|({`[:space:]>]|[.]\/)[.]codex([\/[:space:]"`)]|$)'; then
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
  # 絶対パスは . と .. を解決して正規化してから cwd 配下判定する。
  # 正規化しないと /Users/.../$(basename cwd)/../$(basename cwd)/.codex のような
  # .. を含む形が cwd_lower の prefix 比較に一致せず素通りする。
  # さらに codex 関連の絶対パスは symlink を realpath 相当で解決する。
  # cd $dir && pwd -P で path 中の symlink を解決する。存在しない部分（書き込み対象の
  # .codex/config.toml 等）は親方向に遡って存在するディレクトリで cd し、suffix を結合。
  case "$token" in
    /*)
      token=$(printf '%s' "$token" | sed -E -e 's#/\./#/#g' -e ':a' -e 's#/[^/]+/\.\.(/|$)#/#g' -e 'ta' -e 's#//+#/#g')
      case "$token" in
        *[Cc][Oo][Dd][Ee][Xx]*)
          _try_dir=$token
          _rest=
          while [[ -n "$_try_dir" && "$_try_dir" != "/" && ! -d "$_try_dir" ]]; do
            _rest="/${_try_dir##*/}${_rest}"
            _try_dir=${_try_dir%/*}
            [[ -z "$_try_dir" ]] && _try_dir=/
          done
          if [[ -d "$_try_dir" ]]; then
            _resolved=$(cd "$_try_dir" 2>/dev/null && pwd -P)
            if [[ -n "$_resolved" ]]; then
              token=$(printf '%s' "${_resolved}${_rest}" | tr '[:upper:]' '[:lower:]')
            fi
          fi
          ;;
      esac
      ;;
  esac
  # cwd 配下の絶対パスは相対化してから判定する（mkdir /abs/cwd/.codex 等の回避を防ぐ）。
  # cwd 外の絶対パスだけが /* で許可される。guard-codex-dir.sh と同じ基準。
  token="${token#"$cwd_lower"/}"

  case "$token" in
    # ホーム配下・cwd 外の絶対パスは許可（上で動的展開残留判定の除外と一貫させる）
    # 注: ~ はクォートしてリテラル一致させる。旧実装の "[~]" はクォート内で
    # グロブでなくリテラル 3 文字になり、~/.codex を許可できないバグだった。
    "~/$protected_name"|"~/$protected_name"/*|"\$home/$protected_name"|"\$home/$protected_name"/*|/*)
      continue
      ;;
    # $TMPDIR / ${TMPDIR} 配下も cwd 外（/tmp や /var/folders/...）のため許可
    "\$tmpdir/$protected_name"|"\$tmpdir/$protected_name"/*|"\${tmpdir}/$protected_name"|"\${tmpdir}/$protected_name"/*)
      continue
      ;;
    # $XDG_* / ${XDG_*} 配下も同様に許可
    \$xdg_*"/$protected_name"|\$xdg_*"/$protected_name"/*|\$\{xdg_*\}"/$protected_name"|\$\{xdg_*\}"/$protected_name"/*)
      continue
      ;;
    "$protected_name"|"$protected_name"/*|*"/$protected_name"|*"/$protected_name"/*)
      # 読み取り専用アクセス（上の codex_readonly_ok 判定）は免除する
      if [[ "$codex_readonly_ok" = 0 ]]; then
        echo "ブロック: プロジェクト内の .codex/ ディレクトリへの参照は禁止されています（Cymulate notify エスケープ対策）" >&2
        exit 2
      fi
      ;;
  esac
done

# --- chmod 777 ---
if printf '%s\n' "$command" | grep -qiE '(^|[;&|({`[:space:]/\])chmod[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*777([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: chmod 777 は禁止されています" >&2
  exit 2
fi

# --- sudo ---
if printf '%s\n' "$command" | grep -qiE '(^|[;&|({`[:space:]/\])sudo[[:space:]]'; then
  echo "ブロック: sudo は禁止されています" >&2
  exit 2
fi

exit 0
