#!/usr/bin/env bash
#
# PreToolUse hook (Claude Code 専用): sandbox の excludedCommands にマッチしうる
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
# どこか 1 つがマッチすると、**その行全体**が sandbox 外で走る。filesystem の
# denyRead / denyWrite / allowWrite、network.allowedDomains、credentials の deny が
# まとめて外れる。実測表と設計の経緯は docs/ai-operations.md §10 が正本。
#
# これは Claude Code の仕様であり、除外コマンドを「単独コマンドのときだけ除外する」
# 指定方法は上流に存在しない (2.1.212 時点)。よって hook 側で単独実行を強制する。
#
# ## 判定は粗い fail-closed (設計判断。詳細は docs §10)
#
#   compound な行 (`;` `|` `&` 改行で 2 つ以上の sub-command に割れる行) に
#   除外コマンド名が **単語として現れたら、位置を問わずブロックする**
#
# 当初は上流の正規化 (wrapper / 環境変数代入の剥がし、コマンド語のクォート除去) を
# 写して「コマンド位置に来る場合だけ」ブロックしていたが、レビュー 2 周とも
# 写し漏れが見つかり、そのたびに実測で sandbox が外れた。コマンド位置の判定を
# やめることでその系統の写し漏れは無くなる。**ただし語境界とクォート走査は
# 依然としてシェルのトークナイザの近似**で、写し漏れの余地はそこに移っただけ。
#
# 代償として、`echo "gh のこと"; ls` のように**言及しているだけの行**も止まる。
# この誤ブロックは書き方を変えれば解消でき、見逃し (sandbox が黙って外れる) とは
# 非対称なので許容する。クォート解釈とコメント除去は残してある —
# `gh ... --jq '.[] | .name'` や「コメントで gh に言及しているだけの複数行
# ブロック」は既存 skill / docs の主要な書き方で、ここまで潰すと代償が過大になる。
#
# ## これは境界ではなく lint である
#
# 上流のパーサと完全に一致する保証は無く、想定外の書き方ですり抜ける余地は残る。
# OS が強制する sandbox 本体の代わりにはならない。
#
# ## 効かないもの (意図的な残余リスク)
#
# 除外コマンドを **単独行**で実行する場合は引き続き sandbox 外で走る。単独行でも
# `docker run -v /:/host ...` / `brew install <formula>` (formula の Ruby が動く) /
# `gh extension` のように **sandbox 外での任意コード実行**になりうるので、
# 「単独行なら安全」ではない。`gh *` は sandbox 内から macOS Keychain が届かず
# TLS 検証も通らないため除外リストから外せず、この残余は除去できない。
#

set -euo pipefail

# 文字クラス判定 (case のブラケット・tr) をロケール非依存にする。
# 判定対象はユーザーの日本語コメント等を含む任意のコマンド文字列で、
# ロケール依存の照合順序が入ると環境ごとに結果が変わりうるため pin する。
export LC_ALL=C

input=$(cat)

if ! command -v jq &>/dev/null; then
  # jq 不在時はフェイルセーフでブロック (block-dangerous-commands.sh と同じ姿勢)
  echo "ブロック: jq 未インストールのため sandbox 除外コマンドの混在を確認できません" >&2
  exit 2
fi

# jq が payload を parse できない場合もフェイルセーフでブロックする
# (パースできない入力を「コマンド無し」と読んで素通しすると、判定を持たないまま許可に倒れる)。
if ! command=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  echo "ブロック: PreToolUse の入力を parse できないため sandbox 除外コマンドの混在を確認できません" >&2
  exit 2
fi

if [[ -z "$command" ]]; then
  exit 0
fi

nl=$'\n'
cr=$'\r'
tab=$'\t'
vt=$'\v'
ff=$'\f'

# 早期スクリーニング: sub-command の区切り文字が 1 つも無ければ混在は起こりえない。
# この hook は **全 Bash tool 呼び出し**で走るため、大多数を占める単独コマンドが
# settings 読み込み以降のプロセス起動を踏まないようにする (ここでは外部プロセスを
# 起動しない)。区切りの集合は上流の分割 (program / list / pipeline) に合わせる —
# **改行を落とすと 3 行に分けただけで素通りする**ので必ず含めること。
case "$command" in
  *';'*|*'|'*|*'&'*|*"$nl"*|*"$cr"*) ;;
  *) exit 0 ;;
esac

# --- 除外コマンドのリスト取得 -------------------------------------------------
# Claude Code は user / project / local / managed の各 settings を **merge** して
# excludedCommands を決めるため、こちらも同じ順で存在するものを全部読む。
# 1 つも読めない場合だけ組み込み既定にフォールバックする。フォールバックが必要
# なのは tests/run-hook-tests.sh が隔離 HOME で hook を実行するため — 実設定に
# 依存するとテスト結果が実ユーザー環境の設定に左右される。
# 「読めた上で空」は除外コマンドが 1 つも無い環境なので、フォールバックしない
# (組み込み既定で誤ブロックしないため)。
builtin_globs=('docker *' 'gh *' 'brew *' 'pnpm test:e2e *')

settings_files=()
[[ -n "${HOME:-}" && -r "$HOME/.claude/settings.json" ]] && settings_files+=("$HOME/.claude/settings.json")
[[ -r ".claude/settings.json" ]] && settings_files+=(".claude/settings.json")
[[ -r ".claude/settings.local.json" ]] && settings_files+=(".claude/settings.local.json")
managed="/Library/Application Support/ClaudeCode/managed-settings.json"
[[ -r "$managed" ]] && settings_files+=("$managed")

globs=()
settings_read=0
if [[ ${#settings_files[@]} -gt 0 ]]; then
  if raw_globs=$(jq -r '.sandbox.excludedCommands // [] | .[]' "${settings_files[@]}" 2>/dev/null); then
    settings_read=1
    while IFS= read -r g; do
      [[ -n "$g" ]] && globs+=("$g")
    done <<< "$raw_globs"
  fi
fi
if [[ $settings_read -eq 0 ]]; then
  globs=("${builtin_globs[@]}")
fi

# glob からリテラル前置語だけを取り出す ("gh *" → "gh", "pnpm test:e2e *" → "pnpm test:e2e")。
# 先頭が glob メタ文字の entry ("*" 等) は「全コマンドが除外対象」を意味するので、
# 空 prefix として残し、後段で任意の compound 行に一致させる (危険側に緩めない)。
prefixes=()
match_any=0
# bash 3.2 + `set -u` では空配列の `"${arr[@]}"` が unbound variable になるため、
# 空でも安全な `${arr[@]+...}` 形で展開する。
for g in ${globs[@]+"${globs[@]}"}; do
  p=${g%%[*?[]*}          # 最初の glob メタ文字以降を落とす
  p=${p%"${p##*[! ]}"}    # 末尾空白を落とす
  if [[ -z "$p" ]]; then
    match_any=1
  else
    prefixes+=("$p")
  fi
done
[[ ${#prefixes[@]} -eq 0 && $match_any -eq 0 ]] && exit 0

# --- クォート解釈 -------------------------------------------------------------
# やることは 3 つ:
#   1. クォート内 / エスケープされた区切り文字を **区切りとして数えない**
#      (`gh ... --jq '.[] | .name'` のような単独コマンドを誤ブロックしないため)
#   2. クォートとバックスラッシュを外して語を復元する
#      (`g"h"` / `g\h` のような難読化を語一致で捕まえるため)
#   3. クォート外の `#` から行末までのコメントを落とす。コメントは実行されないので
#      上流も sub-command として数えない — 落とさないと「コメントで gh に言及して
#      いるだけの複数行ブロック」が丸ごとブロックされ、代償が過大になる
#
# 正規表現でクォート span を削除する方式は採らない — `echo "don't"` のように
# 対にならないシングルクォートがあると、実在の区切りごと消えて素通りする。
# クォートが閉じていない場合は解釈を諦め、生のコマンドで分割する (ブロック側に倒す)。
#
# 実装は awk の 1 パス。bash の 1 文字ずつのループでも同じことはできるが、この hook は
# **全 Bash tool 呼び出し**で走るので長い入力で無視できない (実測 2026-08-04 /
# bash 3.2.57 / macOS: 20000 文字で 0.58s/call。awk なら同じ入力が 0.02s/call)。
# 長さで打ち切る分岐 (打ち切った側が誤ブロックする) も要らなくなる。
#
# `prev_raw` は「直前に積んだ文字がクォート外の生の文字か」。リダイレクト複製子
# (`2>&1`) の判定に使う。**クォート文字を読んだ周回でも必ずリセットすること** —
# 残すと `ls >""&gh` のように `>` とクォートを挟んだ形で、実在の区切りの `&` を
# 複製子と誤認して潰してしまう (実測で sandbox が外れた)。
parsed=$(printf '%s' "$command" | awk '
  function flushsep() {
    if (in_s || in_d) { out = out "_"; prev_out = "_" }
    else { out = out "\n"; prev_out = "\n" }
    prev_raw = ""
  }
  BEGIN { bs = "\\"; out = ""; orig = ""; in_s = 0; in_d = 0; prev_raw = ""; prev_out = "" }
  {
    if (NR > 1) { orig = orig "\n"; flushsep() }
    orig = orig $0
    n = length($0)
    i = 1
    while (i <= n) {
      c = substr($0, i, 1)
      lit = ""; raw = ""
      if (in_s) {
        if (c == "\047") { in_s = 0; prev_raw = "" } else lit = c
      } else if (in_d) {
        if (c == "\042") { in_d = 0; prev_raw = "" }
        else if (c == bs) { i++; lit = substr($0, i, 1) }
        else lit = c
      } else if (c == "#" && (prev_out == "" || prev_out == " " || prev_out == "\t" || \
                              prev_out == "\n" || prev_out == "_" || prev_out == ";" || \
                              prev_out == "|" || prev_out == "&")) {
        out = out " "; prev_out = " "; prev_raw = ""
        break            # ここから行末までコメント
      } else if (c == "\047") { in_s = 1; prev_raw = "" }
      else if (c == "\042") { in_d = 1; prev_raw = "" }
      else if (c == bs) { i++; lit = substr($0, i, 1) }
      else if (c == "&") {
        nxt = substr($0, i + 1, 1)
        if (prev_raw == ">" || prev_raw == "<" || nxt == ">") lit = "&"
        else raw = "&"
      } else raw = c
      if (raw != "") { out = out raw; prev_raw = raw; prev_out = raw }
      else if (lit != "") {
        if (lit == ";" || lit == "|" || lit == "&" || lit == "\r") { out = out "_"; prev_out = "_" }
        else { out = out lit; prev_out = lit }
        prev_raw = ""
      }
      i++
    }
  }
  END { if (in_s || in_d) printf "%s", orig; else printf "%s", out }
')

# --- compound かどうか --------------------------------------------------------
# 非空の sub-command が 2 つ以上あれば compound。区切りがクォート内にしか
# 無かった行はここで 1 に戻り、対象から外れる。
# set2 が 1 文字なのは意図的。POSIX では「set2 が短い場合」は unspecified だが、
# BSD tr / GNU tr とも最後の文字で埋める (実測済み)。長さを揃えて書くと
# SC2020 (set2 の重複) の指摘が出るため、揃えずにこのコメントで補う。
seg_count=$(printf '%s' "$parsed" | tr ';|&'"$cr" '\n' | grep -c '[^[:space:]]' || true)
[[ ${seg_count:-0} -le 1 ]] && exit 0

if [[ $match_any -eq 1 ]]; then
  matched="*"
else
  # 除外コマンド名が **単語として** どこかに現れるか。位置 (コマンド位置か引数か)
  # は問わない — 上流の正規化を写す方式が写し漏れで破れたため (冒頭の設計判断)。
  # 区切り文字と **あらゆる空白** を空白 1 個に畳んでから、前後を空白で挟んで
  # 包含判定する。タブを畳まないと、複数行ブロックのタブ字下げ (`;<TAB>gh ...`) で
  # 語の前後が空白にならず検出を素通りする (実測で sandbox が外れた)。
  # set1 = ; | & CR LF TAB VT FF の 8 文字。
  flat=$(printf '%s' "$parsed" | tr ';|&'"$cr$nl$tab$vt$ff" '        ' | tr -s ' ')
  matched=""
  for p in ${prefixes[@]+"${prefixes[@]}"}; do
    if [[ " $flat " == *" $p "* ]]; then
      matched="$p"
      break
    fi
  done
fi

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

分割で解決しない形もあります:

- 標準入力を pipe で渡す形 (cat body.md | $matched ...) — 中間ファイルを使う
  オプション (--body-file / -F <file> 等) に書き換えてください
- 出力を pipe で渡す形 ($matched ... | other) — $matched 内蔵の --jq を使うか、
  いったんファイルに落として次の呼び出しで処理してください
- 出力を変数に受ける形 (x=\$($matched ...)) — コマンド置換は sandbox 内で走るため
  $matched 自体が失敗します。単独で実行して結果を読み、値はリテラルで渡してください
- コード中の文字列として "$matched" に言及しているだけの場合 — 判定は粗い
  fail-closed なので止まります。pipe を外して別呼び出しにするか、語を分割して
  書いてください (シェルのコメント `#` 内の言及はブロックされません)
EOF
exit 2
