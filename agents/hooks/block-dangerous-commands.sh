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
# dotfile glob (.co* / .* / .[c]odex / .cod?x 等) と dotfile brace 展開
# (.co{dex,x} 等) は literal "codex" 文字列を含まないため上の codex パターンでは
# screener を通過しない。実行時のシェル glob/brace 展開で .codex にマッチしうる
# ため、`\.${gap}[a-z]*${gap}[*?[{]` (先頭 . のあと quote-connective の 0+ 英字 +
# glob or brace メタ文字) を検出したら本判定に流す。gap を挟むことで
# `touch ".co"*/x` や `touch ".co"{dex,x}` のような引用符連結による回避を捕捉。
if ! printf '%s' "$input_lower" \
    | grep -qE "r${gap}m|g${gap}i${gap}t|c${gap}h${gap}m${gap}o${gap}d|s${gap}u${gap}d${gap}o|c${gap}o${gap}d${gap}e${gap}x|\\\$|\`|\\.${gap}[a-z]*${gap}[*?[{]"; then
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

# 段階1.5 で使う view として、raw (stage 1 の \X→X 前) の command を保存する。
# printf format の \n / \r は stage 1 の一般的 backslash strip で `n`/`r` に潰されるため、
# `printf 'X\nrm -rf ~' | bash` のような printf format 経由の危険再構成を検出するには
# stage 1 適用前の raw view で extractor を走らせる必要がある。
command_raw=$command

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

# 段階1.5 (issue #56): 再パース経路 (bash -c / eval / <<< / <(...) / echo|printf ... | *sh)
# の quoted 引数を抽出し、command / command_pre_sq の末尾に "; X" として追記する。
# これにより下流の危険判定 (rm -rf ~ / .codex / git push --force / sudo / chmod 777 等) が、
# 再パース対象をトップレベルコマンドとして直接検出する。
#
# 従来の挙動: 段階2 のシングルクォート除去 ($ / ` を含まない sq を unwrap) で偶発的に
# 大半の再パース経路が catch されていた (`bash -c 'rm -rf /'` → `bash -c rm -rf /`)。
# 例外: `~` を含む sq は sentinel 保護で command_for_tilde に quote が残るため、tilde
# 判定の boundary クラス (`'` は非該当) を通過して素通りしていた。また `bash -c '...' &&
# bash -c '...'` のような 2 段目 -c も同じ理由で漏れていた。
#
# 動的展開を含む再パース対象は既存の段階6-7 (line 219/231/259 相当) が別途ブロックする。
# ここで抽出するのは静的リテラルのみで足り、下流判定に流すだけで済む。
_reparse_extract() {
  # wrapper: 代入語 + env/nice 等ラッパー + 絶対パス (segment 先頭アンカーを含まない
  # 「invocation 直前の許容トークン」のみ)。prefix と E receiver の両方から再利用する。
  local wrapper='([A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*[[:space:]]+)*((env|command|nice|exec|nohup|setsid|stdbuf|timeout|ionice|chrt|time)([[:space:]]+([-+][^[:space:]]+|[0-9][^[:space:];&|]*|[A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*))*[[:space:]]+)*([^[:space:];&|]*/)?'
  # prefix: segment 先頭アンカー (`(^|[;&|({`])`) + 空白 + wrapper。
  # 初期 char class に [:space:] は含めない (echo/printf の引数中 shell 名を誤って
  # 「invocation」扱いする FP を防ぐ。既存段階6 判定A の segment-start と一致)。
  local prefix="(^|[;&|({\`])[[:space:]]*${wrapper}"
  local shell='([a-zA-Z]*sh|nu)([[:space:]]+([-+][oO][[:space:]]+[^-+<[:space:];&|][^[:space:];&|]*|(--rcfile|--init-file)[[:space:]]+[^[:space:]]+|--[a-zA-Z][a-zA-Z-]*|[-+][^-[:space:]][^[:space:]]*|<))*'
  local dashc='[[:space:]]+(-[a-z]*c[a-z]*|--command)'
  # C/D/E の receiver 判定用の explicit allowlist (banish / polish / finish 等の非シェルを
  # `[a-zA-Z]*sh` の greedy match で拾わないようにする。A/B は -c/--command/eval の要件で
  # 別途タイトなため loose match でよい)。
  # shell_receiver は shell 名 + 既存 shell と同じ flag 許容 (`bash -s <<<` / `bash --login <<<`
  # のような shell と再パーストークンの間に挟まる option フラグを取りこぼさないため)。
  local shell_strict='(bash|zsh|dash|sh|fish|ksh|mksh|ash|tcsh|csh|yash|posh|nu)'
  local shell_receiver="${shell_strict}"'([[:space:]]+([-+][oO][[:space:]]+[^-+<[:space:];&|][^[:space:];&|]*|(--rcfile|--init-file)[[:space:]]+[^[:space:]]+|--[a-zA-Z][a-zA-Z-]*|[-+][^-[:space:]][^[:space:]]*|<))*'
  # A. *sh -c / --command: 第 1 引数のみが code (第 2 引数以降は $0/$1...)。
  # single-arg 抽出でよい。
  printf '%s' "$1" | grep -oE "${prefix}${shell}${dashc}[[:space:]]+'[^']*'" \
    | sed -E "s/.*'([^']*)'\$/\\1/"
  printf '%s' "$1" | grep -oE "${prefix}${shell}${dashc}"'[[:space:]]+"[^"]*"' \
    | sed -E 's/.*"([^"]*)"$/\1/'
  # B. eval: 全引数を空白連結して再評価するため multi-arg 対応が必要
  # (例: `eval 'rm -rf' '~'` → 内部で `rm -rf ~` を評価しチルダ展開が発生)。
  # segment 終端まで region を抽出し、外側クォートを除去する。
  printf '%s' "$1" | grep -oE "${prefix}eval[[:space:]]+[^;&|(){}]+" \
    | sed -E "s/.*eval[[:space:]]+//; s/['\"]//g; s/\\\\[nr]/;/g; s/\\\\t/ /g"
  # C. *sh <<< 'X': here-string は単一 arg のみが reparse 対象。single-arg でよい。
  # receiver は *sh/nu 系のみに限定 (cat/grep 等の非シェル <<< は単なる stdin 供給)。
  # `bash -s <<< 'X'` のような option フラグ挟みも shell_receiver で許容。
  printf '%s' "$1" | grep -oE "${prefix}${shell_receiver}[[:space:]]*<<<[[:space:]]*'[^']*'" \
    | sed -E "s/.*'([^']*)'\$/\\1/"
  printf '%s' "$1" | grep -oE "${prefix}${shell_receiver}"'[[:space:]]*<<<[[:space:]]*"[^"]*"' \
    | sed -E 's/.*"([^"]*)"$/\1/'
  # D. *sh|source|. <(echo|printf ...): echo/printf の全引数が空白 (echo) / フォーマット
  # 展開後 (printf) の文字列として script 側に流れる。`(...)` 内の region を抽出して
  # クォート除去する。receiver 制約で head/diff 等の process subst 引数化は除外。
  printf '%s' "$1" | grep -oE "${prefix}(${shell_receiver}|source|\\.)[[:space:]]+<\\((echo|printf)[[:space:]]+[^)]+\\)" \
    | sed -E "s/.*<\\((echo|printf)[[:space:]]+//; s/\\)\$//; s/['\"]//g; s/\\\\[nr]/;/g; s/\\\\t/ /g"
  # E. echo|printf ... | *sh|nu: echo/printf の全引数が pipe 経由で shell に再パースされる。
  # `|` までの region を抽出してクォート除去。receiver は allowlist + word boundary で
  # banish/polish 等の greedy match を排除。option フラグ挟み (`| bash -s`)、絶対パス
  # (`| /bin/bash`)、env 等ラッパー (`| env bash`) も wrapper 経由で許容。
  printf '%s' "$1" | grep -oE "(^|[;&|({\`])[[:space:]]*(echo|printf)[[:space:]]+[^|;&(){}]+\\|[[:space:]]*${wrapper}${shell_receiver}([[:space:]]|\$|[;&|])" \
    | sed -E "s/.*(echo|printf)[[:space:]]+//; s/[[:space:]]*\\|.*//; s/['\"]//g; s/\\\\[nr]/;/g; s/\\\\t/ /g"
}
# 再パーストークンを含まない入力は関数呼び出しごと skip する (hot path 最適化。
# 通常 `git status` / `ls -la` 等は 0 fork でこの段階を抜ける)。
# bash =~ で ERE を使う (case のリテラル空白依存を回避。tab 区切り `bash<TAB>-c<TAB>'X'` や
# 結合フラグ `bash -ce 'X'` `-ec` `-cx` 等が case guard を通過して bypass にならないよう
# extractor 側の regex 許容度と揃える)。
_reparse=""
_reparse_re='[[:space:]]-[a-z]*c[a-z]*[[:space:]]|--command|(^|[^A-Za-z0-9_])eval[[:space:]]|<<<|<\(|\|[[:space:]]*((bash|zsh|dash|sh|fish|ksh|mksh|ash|tcsh|csh|yash|posh|nu|env|command|nice|exec|nohup|setsid|stdbuf|timeout|ionice|chrt|time)([[:space:]]|$|[;&|])|/)'
# extractor は raw (stage 1 前) の view で走らせる。stage 1 の \X→X 適用後だと
# `printf 'X\nY' | bash` の \n が n に潰れて `XnY` になり、danger 判定が Y の rm を
# 見つけられなくなるため。extractor 側で \n / \r → `;` 置換を行い、bare な segment 分割で
# 下流判定に流す。ANSI-C $'...' は上で全面ブロック済み、backslash-space 越しの `bash\ -c`
# 等の稀な escape 形は extractor が拾えないが、AGENTS.md で禁止済みなので影響は小さい。
if [[ "$command_raw" =~ $_reparse_re ]]; then
  _reparse=$(_reparse_extract "$command_raw")
fi
if [[ -n "$_reparse" ]]; then
  # 各抽出片を `;` で連結 (改行 → `;`)。抽出片は最外側 quote が剥がれた bare fragment
  # のため、下流の sq-strip / sentinel 保護のいずれにも影響しない (`rm -rf ~` が bare で
  # 現れ、tilde 判定の boundary クラスに合致する)。
  # bash param expansion で subshell を避ける (printf|tr より 3 fork 削減)。
  _reparse_joined=${_reparse//$'\n'/;}
  command="$command; $_reparse_joined"
  command_pre_sq="$command_pre_sq; $_reparse_joined"
fi

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
  echo "ブロック: コマンド名トークンに動的展開を含むコマンドは安全側で禁止されています（危険コマンド名の動的構築対策）。コマンド名は静的リテラルで書くか、コマンド列をスクリプトファイルに書いて bash <ファイル> で実行してください。" >&2
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

# リダイレクト演算子の表記ゆらぎを、「書き込み系リダイレクトが在るか」を問う全判定の
# 手前で 1 度だけ正規化する。この hook はセグメントを `; & | ( )` で分割してから判定
# するため、`&` を含む演算子は演算子と書き込み先が別セグメントに割れてしまう。
# 同型の設計判断として `>|` → `>` の正規化が元から入っており (noclobber の有無しか
# 違わないので security 判定に影響しない)、そこへ fd リダイレクトの 2 形を足す。
#
# 段1: fd 複製 (`2>&1` / `>&2` / `>&-` / `2>&1-`) を空白へ潰す。これは「既存 fd の
#   複製」でファイルへは書かないが、`&` が区切りに該当するため `... 2>` と `1` に割れ、
#   前半に孤立した `2>` が `_write_redirect_re` の `[0-9]+>>?([^&]|$)` に `$` 境界で
#   誤マッチし、読み取り専用コマンドまで書き込み文脈と判定されていた
#   (issue #284。`cmd ... 2>&1 | tail` 系が破綻する)。置換先を placeholder 文字列
#   ではなく空白にするのは、区切り文字・glob メタ文字・`.codex` マッチ・readonly
#   allowlist 語・小文字化のいずれとも衝突しないため (文字列だと全部について衝突
#   分析が要る)。fd 番号も一緒に消すので、readonly walker のセグメント先頭に裸の
#   `1` が立つ問題も同時に解消する。区切りが隣接する `cmd 2>&1|2>&1` /
#   `cmd >&1>&2` は 1 個目のマッチが右境界を消費して 2 個目を取りこぼすが、
#   段 1a / 1b をそれぞれ収束まで反復することで解消している (後述)。
#   **対象は `>&` の後ろの word が「まるごと」数字列 (末尾 `-` 可) または `-` 単体の
#   形に限定する**。境界は 3 つ要る (段 1 が 2 本の -e に分かれているのはこのため):
#     - `&>` との区別: `&>file` / `&>>file` は `>file 2>&1` の bash 短縮形 = 本物の
#       write redirect。`&` が `>` に先行するのでこの正規表現には一切マッチしない
#     - 左 (`(^|[^A-Za-z0-9_./-])[0-9]+`): `>&` の直前の数字が「明示 fd 番号」なのか
#       「直前の word の末尾」なのかを区別する。境界が無いと
#       `echo x > file2>&1` の `file2` の `2` まで fd 番号と誤認して食い、書き込み先が
#       `file` に化ける。実測 2026-08-07: `bash -c 'echo hi > file2>&1'` が生成する
#       ファイルは `file2`。影響は fail-closed 側 (`> .codex2>&1` は `.codex2` という
#       **ファイル**を作るだけなのに `.codex` と読めてブロックされていた) だが、
#       判定 view が実際のコマンドと食い違うこと自体が誤り。
#       左境界にマッチしなかった `>&<数字>` は 2 本目の -e が拾う (直前の word を
#       食わずに `>&1` だけを消す)
#     - 右: `([^A-Za-z0-9_./-]|$)` で word 末尾を要求する。**これが無いと
#       `>&1/../.codex/evil` の `>&1` だけを fd 複製と誤認して丸ごと消し、本物の
#       書き込みが判定から消えて allow に転ぶ** (fail-open)。実測 2026-08-07:
#       `bash -c 'cat src.txt >&1/../.codex/evil'` は exit=0 で `.codex/evil` を
#       実際に生成する。数字始まりのディレクトリ (`1/` `2024/`) はエージェント自身が
#       作れるので前提条件は容易に整う
#   `>&` と数字の間の空白も食う (`>& 1` / `2>& 1`)。これらは bash では fd 複製で、
#   実測でもファイルは生成されない (2026-08-07、汚染のない一時 dir で `ls -A` 確認)。
# 段2: 段1 で消えずに残った `>&` は、定義上「word が数字でも `-` でもない」形なので
#   bash では `&>word` と同義の **両ストリーム → ファイル書き込み**。`> ` に書き換えて
#   `&` を除去する。空白の有無を問わずファイルが作られることを 2026-08-07 に実測
#   (`echo hello >& out.txt` / `echo hello >&out.txt` の両形で out.txt 生成、
#   `ls /nonexistent >& out.txt` で stderr も捕捉)。これをしないと演算子
#   (`echo x >`) と書き込み先 (`.co*/foo`) が
#   別セグメントに分かれ、`_check_glob_seg` の component 検査が書き込み先に一度も
#   当たらない。**この素通りは issue #284 の修正前から開いていた** (旧 hook で
#   `echo x >& .co*/foo` が exit=0 になることを実測)。literal 形 (`>&.codex/log`) は
#   後段の `.codex` 文字列検出が拾っていたため、glob 形にのみ穴が残っていた。
# 段3: `>|` (clobber redirect) を `>` へ。`|` を含むが pipe ではないため、分割前に
#   潰しておく必要がある。`\|` ではなく `[|]` と書くのは、ERE における `\|` の
#   意味が POSIX 未定義で実装依存 (BSD / GNU で割れうる) なため。
# 段1 と段2 を 1 本の正規表現にまとめられないのは、**置換後の文字列が違う**ため
# (段1 は空白 1 個、段2 は `> `)。パターンの複雑さの問題ではなく、段1 で消費され
# なかった `>&` だけが段2 に残るという排他的な残余関係になっている。
# 既知のスコープ外: 入力側 fd 複製 `<&N` は同型の分割を起こすが、書き込み文脈判定に
# 関与しないため issue #284 では扱わない。
# 境界は **shell の word 区切り** で定義する。「パス文字でない文字」(`[^A-Za-z0-9_./-]`)
# で書くと受理側の口が広すぎて破れる: `!` `#` `%` `+` `,` `:` `=` `?` `@` `[` `]` `^` `~`
# はいずれもファイル名に使える文字なので、`>&1+/../.codex/evil` のような形が
# 「fd 複製 + 区切り」に見えてマスクされ、本物の書き込みが判定から消える。
# 2026-08-07 に 13 文字すべてを実測: bash は 13/13 で `.codex/` にファイルを生成し、
# 「パス文字でない」版の hook は 13/13 を allow していた (fail-open)。
# 区切りだけを列挙する側に倒せば、判断できない文字は「word の続き」= 本物の
# 書き込み先として扱われ、外したときの被害が fail-closed 側に出る。
# quote (`"` `'`) や `$` / backtick を含めないのも同じ理由 (含めると
# `>&1"/../.codex/evil"` が通る)。
# 空白側は `[[:space:]]` ではなく **`[[:blank:]]` (space + tab のみ)** を使う。
# `[[:space:]]` は VT(0x0B) / FF(0x0C) / CR(0x0D) にもマッチするが、**bash は
# この 3 文字を word 区切りとして扱わない** — ファイル名の一部になる。
# 2026-08-07 実測: `cat src >&1<VT|FF|CR>/../Zdir/evil` は 3/3 で Zdir/evil を生成し、
# `[[:space:]]` 版の hook はこれを allow していた (パス文字 13 種と同型の fail-open)。
# 改行を列挙しないのは sed が行単位で処理するため — 行末は `$` 側が拾う。
# 左右で集合が違う。**同じ「区切り」という語だが問いが違う**ので共有しない:
#   - 右 (`_fd_word_end_sep`): 「fd 番号の word がここで終わるか」。`&` `<` `>` を
#     含める — `>&1>foo` の `>` や `>&1&` の `&` は確かに word の終端 (消費した文字は
#     `\2` / `\3` で書き戻すので後続の判定からは失われない)
#   - 左 (`_fd_word_start_sep`): 「この数字が明示 fd 番号として word の先頭にあるか」。
#     **`&` `<` `>` を含めてはいけない** — これらは `>&` `<&` というリダイレクト演算子
#     自身の構成文字なので、境界として認めると `>&1>&2` の 2 個目の `&` が左境界に
#     使われ、`&1>&2` ごと消えて演算子 `>&` が残り、段 2 が `> ` (書き込み) に化かす。
#     実測 2026-08-07: 含めた版では `cat .codex/config.toml >&1>&2` が exit=2。
#     除いた版では両方の fd 複製が消えて exit=0 (bash でも書き込みは発生しない)
_fd_word_start_sep='[[:blank:];|()]'
_fd_word_end_sep='[[:blank:];&|()<>]'
# 段 1 は収束するまで反復する。1 回では、fd 複製が区切りを挟んで連続する形
# (`2>&1|2>&1` / `>&1>&2`) で **1 個目のマッチが右境界を消費してしまい**、2 個目に
# 左境界が残らず取りこぼす。取りこぼした fd 番号が裸でセグメント先頭に立ち、readonly
# 免除が外れて読み取りが過ブロックされていた (fail-closed で main も同結果なので
# リグレッションではなかったが、機構としては直せる)。反復は fail-open 方向には
# 倒れない — 各パスが消すのは「両側に境界がある fd 複製」だけで、本物の書き込みは
# 境界にマッチしないので残る。上限 8 は expand_assignments と同じ無限ループ防止。
#
# **段 1a を先に収束させてから段 1b を回す**。同じ sed の -e に並べると、1b が先に
# `>&1` を消してしまい、1a が拾うはずだった裸の fd 番号が残る
# (`ls .codex 2>&1|2>&1` → 1a が `|` を境界として消費 → 残り `2>&1` に左境界が
# 無い → 1b が `>&1` だけ消して `|2 ` になり、裸の `2` がセグメント先頭に立つ)。
_normalize_fd_redirects() {
  local _cur=$1 _prev _i
  _i=0
  while [ "$_i" -lt 8 ]; do
    _i=$((_i + 1))
    _prev=$_cur
    _cur=$(printf '%s' "$_cur" | sed -E \
      "s/(^|${_fd_word_start_sep})[0-9]+>&[[:blank:]]*([0-9]+-?|-)(${_fd_word_end_sep}|\$)/\\1 \\3/g")
    [ "$_cur" = "$_prev" ] && break
  done
  _i=0
  while [ "$_i" -lt 8 ]; do
    _i=$((_i + 1))
    _prev=$_cur
    _cur=$(printf '%s' "$_cur" | sed -E \
      "s/>&[[:blank:]]*([0-9]+-?|-)(${_fd_word_end_sep}|\$)/ \\2/g")
    [ "$_cur" = "$_prev" ] && break
  done
  # 残った `>&` (word が数字でも `-` でもない = 両ストリーム → ファイル書き込み) と
  # `>|` は反復の必要が無いので、収束後に 1 度だけ適用する。
  printf '%s' "$_cur" | sed -E \
    -e 's/>&[[:blank:]]*/> /g' \
    -e 's/>[|]/>/g'
}

# 動的展開と書き込み系リダイレクト演算子の組み合わせも同様に安全側ブロックする。
# 例: echo x > .$(echo codex)/config.toml → 実行時に .codex/config.toml へ書き込み。
# 対象演算子: > / >> / >| / &> / &>> / N> / N>> （N は fd 番号）
# 入力リダイレクト < / << / <<< は対象外（書き込み先がファイルでない）。fd 複製
# (`>&N` / `>&-`) も同じ理由で対象外だが、`>&word` は上記のとおり本物の書き込みなので
# 対象に含める — どちらも _normalize_fd_redirects が判定前に振り分ける (issue #284)。
# この判定に限り、2026-07-07 の実 FP ラチェットとして 2 つの除外を適用する
# (.codex 参照判定・書き込み系コマンド判定には適用しない — 安全側期待を維持):
#   除外1: リダイレクト先がデバイス系リテラル (/dev/null, /dev/stdout, /dev/stderr,
#     /dev/tty) はファイル構築に使えない。`diff a b >/dev/null 2>&1` のような
#     出力破棄が変数展開と同居するだけでブロックされていた。/dev/nullx 等の
#     見せかけは末尾境界 ([^A-Za-z0-9_/]|$) で除外されない
#   除外2: 読み取り専用イントロスペクションのコマンド置換
#     $(pwd) / $(which WORD) / $(command -v WORD) / $(git rev-parse ARGS)。
#     WORD は先頭ドット禁止 ([A-Za-z0-9_-] 始まり) で `which .codex` は除外されない。
#     git rev-parse の引数はドット・スラッシュなしのフラグ/ref 形のみ。
#     `ls -la "$(which claude)" 2>/dev/null` のような読み取りが FP になっていた。
#     なお $(...) の中身は前段の nested 展開で command 末尾に複製済みのため、
#     中身の危険コマンドは他の判定が引き続き見る
# 順序が重要: (1) デバイスリダイレクト除去 → (2) リダイレクト先に現れる
# コマンド置換を保護マーカー化 (`echo x > "$(which claude)"` のような
# 「置換結果への書き込み」= バイナリ上書き等は除外2 の対象にせずブロック維持)
# → (3) 読み取り専用イントロスペクション置換の除去。
residual_redirect=$(_normalize_fd_redirects "$residual" | sed -E \
  -e 's#((^|[^&0-9])>[>|]?|&>>?|[0-9]+>>?)[[:space:]]*/dev/(null|stdout|stderr|tty)([^A-Za-z0-9_/]|$)#\2\4#g' \
  -e 's#(>[>|]?[[:space:]]*"?)\$\(#\1\$REDIRECT_TARGET_SUBST(#g' \
  -e 's/\$\((pwd|which[[:space:]]+[A-Za-z0-9_-][A-Za-z0-9_.-]*|command[[:space:]]+-v[[:space:]]+[A-Za-z0-9_-][A-Za-z0-9_.-]*|git[[:space:]]+rev-parse([[:space:]]+[A-Za-z0-9_@{}=-]+)*)\)/ /g')
if printf '%s' "$residual_redirect" | grep -qE '\$\(|`|\$[a-zA-Z_{]' \
  && printf '%s' "$residual_redirect" | grep -qE '(^|[^&0-9])>[>|]?[^&]|&>>?[^&]|[0-9]+>>?[^&]'; then
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

# --- 書き込み系コマンド + dotfile glob (.codex にマッチしうる) ---
# `rm -rf .co*` / `touch .co*/x` / `mkdir .[Cc]odex` / `echo x > .co*/foo` 等は
# literal `.codex` を含まないため後段の .codex 検出を素通りするが、実行時の
# シェル glob 展開で .codex にマッチしうる。segment 単位で「書き込み文脈」
# (write コマンド or write redirect) を判定し、引数の各 `/`-区切り component
# を bash glob として `.codex` にマッチするか検査、マッチしたらブロック。
#   - `.co*` → glob `.co*` は `.codex` にマッチ → block
#   - `.git*` / `.[Gg]itignore` → マッチしない → allow
#   - `.[Cc]odex` / `.[!x]odex` → マッチ → block
#   - `../.codex*` → component `.codex*` が `.codex` にマッチ → block
#   - `echo x > .co*/foo` → write redirect 文脈 → target の `.co*` が block
#   - `.co{dex,foo}` → brace 展開結果 `.codex` が block
#   - `command rm -rf .co*` / `env rm -rf .co*` → wrapper 透過 grep で write 判定
#   - `tar --directory=.co*` / `unzip -d.co*` → オプション連結形も派生候補で block
#   - `cat .co*` → read-only 文脈 (write cmd でも redirect でもない) → allow
# sed は `-i` フラグ付き (BSD `-i ''` / GNU `-i.bak`) のみ書き込み扱い
# セグメント分割は `; & |` のみ (brace `{}` は展開文法で分割対象外)
_seg_seps=';&|()'
# rsync / tar / unzip / curl / wget / cpio / ditto は literal 形なら後段の `.codex`
# 文字列検出で止まるが、glob 形 (`.co*`) は
# ここで書き込み文脈と認識されないと `_check_glob_seg` の component 検査に入らず素通り
# していた (issue #284 で rsync / tar、#288 で残り 5 つ)。追加先は本判定用の
# `_write_cmd_names` のみで、430 行の
# `write_cmds` (動的展開 + 書き込み系コマンドの安全側ブロック) には足さない —
# あちらに足すと `tar -xf "$f"` のような日常形まで誤ブロックが広がる。
# 副作用として 3 種類の FP が増える。いずれも fail-closed 方向で、`.codex` 保護 (#190)
# の方針と整合するため許容する (成立には同一セグメントに `.codex` にマッチする glob が
# 要るので、実運用での遭遇率は低い)。実測日は #284 分 (rsync / tar) が 2026-08-07、
# #288 分 (残り 5 つ) が 2026-08-09。いずれも追加前 exit=0 → 追加後 exit=2:
#   - 読み取り系 (`tar -tf x.tar '.co*'` / `unzip -l .co*`)
#   - basename が列挙済みコマンドのパス。`_write_cmd_boundary_re` の先行文字クラスが
#     `/` を含むため、`cat build/tar .co*` / `cat build/curl .co*` のような形も
#     書き込み文脈と判定される
#   - **`.co*` を書き込み先以外の引数に取る形** (読み取り元: `rsync -a .co*/ dst/` /
#     `rsync --dry-run -a .co*/ dst/` / `tar -cf out.tar .co*`、パスですらない引数:
#     `curl https://example.com/.co*` の URL)。`_check_glob_seg` は
#     引数の**位置を区別せず**
#     セグメント内の全引数を検査するので、コピー元とコピー先を分けられない。
#     区別するには「どの引数が書き込み先か」をコマンドごとに知る必要があり、
#     列挙型ブロックリストの枠を超える (#289 の射程)
# **列挙方式なので、塞がるのはここに書いたコマンドだけ**。この構造的限界は #288 の
# 追加後も変わらない — 個々の穴を塞いでも「列挙に無いコマンド」の集合は開いたまま。
# glob 経路を網羅する統制の本体は sandbox の `denyWrite` 側にあり (PR #292 / #289 の
# 結論)、この hook はその多層防御 + sandbox が届かない経路の一次防御として維持する。
# **この hook が担うのは Bash 経路だけ** — file 編集 tool 経路は `guard-codex-dir.sh`
# の担当で、ここは届かない。経路の内訳と担当は docs/ai-operations.md §10 に 1 箇所だけ
# 書く方針なので、ここには複製しない。
_write_cmd_names="rm|chmod|chown|shred|rsync|tar|unzip|curl|wget|cpio|ditto|${write_cmds}"
_write_cmd_boundary_re="(^|[[:space:]/\\])(${_write_cmd_names})([[:space:]]|$)"
_sed_boundary_re='(^|[[:space:]/\\])sed([[:space:]]|$)'
_sed_inplace_re='(^|[[:space:]])-[a-zA-Z]*i[a-zA-Z]*(\.[a-zA-Z0-9]*)?([[:space:]]|$)'
_write_redirect_re='(^|[^&0-9])>[>|]?([^&]|$)|&>>?([^&]|$)|[0-9]+>>?([^&]|$)'
# bash glob → ERE 変換。順序: `.` エスケープ → `*` → `.*` → `?` → `.` → `[!...]` → `[^...]`
_glob_to_ere() {
  local _g=$1
  _g=${_g//./\\.}
  _g=${_g//\*/.*}
  _g=${_g//\?/.}
  _g=${_g//\[\!/[^}
  printf '%s' "$_g"
}
# `.codex` にマッチしうる component (glob 表記) か判定
_matches_codex() {
  local _comp=$1 _re
  [[ -z "$_comp" ]] && return 1
  # 先頭が `.` かワイルドカード (`*` `?` `[`) でなければ `.codex` の 1 文字目に
  # 対応できないので、ERE 変換 (subshell を 1 つ起こす) の前に落とす。長い引数を
  # component ごとに検査する経路のコストがこれで線形側に寄る。
  case "$_comp" in
    [.*?[]*) ;;
    *) return 1 ;;
  esac
  _re=$(_glob_to_ere "$_comp")
  [[ ".codex" =~ ^${_re}$ ]]
}
# arg の brace 展開 `{a,b,c}` を全パターンに展開して 1 行ずつ stdout に出力。
# 未対応: ネスト `{a,{b,c}}` は再帰で解ける。空 alt (`{,x}`) は空要素として扱う。
_expand_braces() {
  local _in=$1 _pre _rest _mid _post _alt _alts
  case "$_in" in
    *"{"*","*"}"*)
      _pre="${_in%%\{*}"
      _rest="${_in#*\{}"
      _mid="${_rest%%\}*}"
      _post="${_rest#*\}}"
      IFS=, read -r -a _alts <<< "$_mid"
      for _alt in "${_alts[@]}"; do
        _expand_braces "${_pre}${_alt}${_post}"
      done
      ;;
    *)
      printf '%s\n' "$_in"
      ;;
  esac
}
# 候補文字列を `/` 区切り component に割り、`.codex` にマッチする glob があれば
# ブロックする。$2 はメッセージに出す元の引数。
# block はこの関数から直接 exit する — return にすると呼び出し側で握り潰されて
# fail-open に倒れる。
_check_components() {
  local _argfull=$2 _rest=$1 _comp
  [[ -z "$_rest" ]] && return 0
  while :; do
    _comp="${_rest%%/*}"
    if _matches_codex "$_comp"; then
      echo "ブロック: 書き込み文脈の引数に .codex にマッチしうる glob/brace ($_argfull) が指定されています（Cymulate notify エスケープ対策）" >&2
      exit 2
    fi
    case "$_rest" in
      */*) _rest="${_rest#*/}" ;;
      *) break ;;
    esac
  done
}
_check_glob_seg() {
  local _seg=$1 _arg _expanded _tail _optval _seg_lower _seg_nodev
  _seg="${_seg#"${_seg%%[![:space:]]*}"}"
  [[ -z "$_seg" ]] && return 0
  _seg_lower=$(printf '%s' "$_seg" | tr '[:upper:]' '[:lower:]')
  # 書き込み文脈判定: (a) 書き込み系コマンドが token 境界で存在 (wrapper 透過)
  #   (b) sed が token 境界で存在 かつ segment に -i (or -i.bak) が存在
  #   (c) 非デバイス write redirect が存在 (`head foo 2>/dev/null` の device
  #   破棄は write 扱いしない)
  _seg_nodev=$(printf '%s' "$_seg" | sed -E 's#((^|[^&0-9])>[>|]?|&>>?|[0-9]+>>?)[[:space:]]*/dev/(null|stdout|stderr|tty)([^A-Za-z0-9_/]|$)#\2\4#g')
  if ! [[ "$_seg_lower" =~ $_write_cmd_boundary_re ]] \
     && ! { [[ "$_seg_lower" =~ $_sed_boundary_re && "$_seg" =~ $_sed_inplace_re ]]; } \
     && ! [[ "$_seg_nodev" =~ $_write_redirect_re ]]; then
    return 0
  fi
  local _args
  read -r -a _args <<< "$_seg"
  for _arg in "${_args[@]}"; do
    _arg="${_arg//[\"\']/}"
    case "$_arg" in
      *[\<\>\&\|]*)
        _arg="${_arg##*[\<\>\&\|]}"
        ;;
    esac
    _arg=$(printf '%s' "$_arg" | tr '[:upper:]' '[:lower:]')
    # brace 展開を全パターンに解いてから component-wise glob match
    while IFS= read -r _expanded; do
      _check_components "$_expanded" "$_arg"
      # オプションと値が 1 トークンに連結された形 (`--directory=.co*` / `-C.co*`) は、
      # 先頭 component にオプション文字列ごと入って `.codex` にマッチせず素通りする
      # (issue #311)。元の文字列は**置換せず**派生候補として足す — 前処理で削って
      # しまうと、境界の見誤りが「危険な形を無害な形に化かす」fail-open として出る。
      # 値の中にさらに `=` がある形 (`--directory=x=.co*`) も外れないよう、
      # 最初の 1 つではなく `=` の位置ごとに後ろを候補にする。
      # 候補は**最初の `/` まで**に切る — その先の component は元文字列の検査で
      # 既に見ており、切らずに `_check_components` へ渡すと `/` 分割を `=` の
      # 個数だけやり直して O(n^3) になる (`a=/a=/…` 形で 1.8KB / 82s を実測)。
      # `=` では分割しない: `[=e=]` のような等価クラスを含む glob を割ると
      # マッチしなくなり fail-open に倒れる。
      _tail=$_expanded
      while [[ $_tail == *=* ]]; do
        _tail=${_tail#*=}
        _check_components "${_tail%%/*}" "$_arg"
      done
      case "$_expanded" in
        -*)
          _optval=${_expanded#-}
          while [[ $_optval == [a-z0-9]* ]]; do _optval=${_optval#?}; done
          # 英数字だけの値 (`-Ctmp`) は候補が空になるが、`.codex` にマッチする glob は
          # 必ず非英数字 (`.` `*` `?` `[`) を含むので危険側は漏れない。
          _check_components "$_optval" "$_arg"
          ;;
      esac
    done <<< "$(_expand_braces "$_arg")"
  done
}
# 単一 segment (大多数のケース) は tr/here-string を回避。
# リダイレクト演算子の正規化 (fd 複製 / `>&word` / `>|`) は _normalize_fd_redirects が
# まとめて行う。この view は後段の codex_readonly_ok 判定でも使い回すため、hook 1 回の
# 実行につき 1 度しか計算しない (同じ計算を各 if で独立に走らせない — has_dynamic と
# 同じ方針)。
_command_norm=$(_normalize_fd_redirects "$command")
case "$_command_norm" in
  *[";&|()"]*)
    while IFS= read -r _seg; do
      _check_glob_seg "$_seg"
    done <<< "$(printf '%s' "$_command_norm" | tr "$_seg_seps" '\n')"
    ;;
  *)
    _check_glob_seg "$_command_norm"
    ;;
esac

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
  # 判定 2 (書き込み系リダイレクトの有無) と判定 3 (セグメント先頭コマンド) は
  # glob 経路と同じ正規化 view ($_command_norm) で行う。素の $command で見ると
  # `>&file` (両ストリーム → ファイル) が既存パターンのどれにもマッチせず、書き込みを
  # 含むコマンドに読み取り免除を与えてしまう。正規化後は `> file` になるので判定 2 が
  # 拾う (issue #284)。判定 2 のパターンは _write_redirect_re と同じ問い
  # (「書き込み系リダイレクトが在るか」) なので、リテラルを複製せず変数を共有する。
  if ! printf '%s' "$_command_norm" | grep -qE "$_write_redirect_re"; then
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
    # 正規化前の $command で分割すると `ls .codex 2>&1` が `ls .codex 2>` と `1` に
    # 割れ、裸の `1` が readonly allowlist に無いため免除が外れる (issue #284)。
    done <<< "$(printf '%s' "$_command_norm" | tr ';&|(){}' '\n\n\n\n\n\n\n')"
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

protected_name='.codex'
# command を 1 度だけ小文字化し、それ以降は全部小文字で比較する
# （macOS APFS 想定で `.Codex` 等も拾う）。`$HOME` はシェル展開されない
# リテラル文字列なので、小文字化された `$home` をパターンに含めて許可判定する。
cwd_lower=$(pwd -P | tr '[:upper:]' '[:lower:]')
normalized_command=$(tr '[:upper:]' '[:lower:]' <<<"$command" | tr ';&|(){}<>' '        ')
# set -f: unquoted 展開は word splitting のみが目的。glob 展開を許すと
# `cat .co*` のようなトークンが cwd の実ファイル (.codex 等) に展開され、
# 同一コマンドの判定が実行ディレクトリの中身に依存してしまう (非決定的な誤ブロック)。
set -f
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
set +f

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
