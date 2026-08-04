#!/usr/bin/env bash
#
# PreToolUse hook (Claude Code 専用): sandbox の excludedCommands にマッチする
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
# どこか 1 つがマッチすると、**その行全体**が sandbox 外で走る。
#
# 実測 (2026-08-04 / Claude Code 2.1.212 / macOS Seatbelt。`~/` は allowWrite 外):
#   touch ~/x.tmp                                → Operation not permitted (sandbox 内)
#   brew --version > /dev/null && touch ~/x.tmp  → 成功 (sandbox 外)
#   touch ~/x.tmp; gh --version                  → 成功 (sandbox 外。gh は後ろでもよい)
#   echo "... gh --version ..."; touch ~/x.tmp   → Operation not permitted (文字列言及は非マッチ)
#
# これは Claude Code の仕様であり、除外コマンドを「単独コマンドのときだけ除外する」
# 指定方法は上流に存在しない (2.1.212 時点)。よって hook 側で単独実行を強制する。
#
# ## これは境界ではなく lint である
#
# 本 hook はコマンド文字列を自前で解釈する。上流の sub-command 分割と正規化を
# 下記のとおり写しているが、**完全な一致は保証できない**。想定外の書き方で
# すり抜ける余地は残るので、「回避不能な境界」ではなく「事故防止の lint」として
# 扱うこと。sandbox 本体 (OS 強制) の代わりにはならない。
#
# 上流実装 (2.1.212 バイナリの文字列から確認) に合わせている点:
#   - sub-command 分割は tree-sitter の program / list / pipeline のみを降下する。
#     すなわち区切りは `;` `|` `&` (`&&` `||` を含む) と改行だけで、
#     **コマンド置換 `$(...)` / バックティック / subshell `(...)` / group `{...}` は
#     降下対象ではない** (= それ単体では sandbox は外れない)
#   - 照合前に wrapper コマンド (command / builtin / noglob / nohup / nice / time /
#     stdbuf / timeout) と環境変数代入を剥がし、コマンド語のクォートと
#     バックスラッシュを外す
#   - 照合は prefix 一致 (`t === prefix || t starts with prefix + " "`)
#
# ## 効かないもの (意図的な残余リスク)
#
# 除外コマンドを **単独行**で実行する場合は引き続き sandbox 外で走る。単独行でも
# `docker run -v /:/host ...` / `brew install <formula>` (formula の Ruby が動く) /
# `gh extension` のように **sandbox 外での任意コード実行**になりうるので、
# 「単独行なら安全」ではない。`gh *` は macOS Keychain が sandbox 内から届かない
# ため除外リストから外せず (実測: sandbox 内の `gh auth status` は
# `The token in keyring is invalid`)、この残余は除去できない。
# 詳細は docs/ai-operations.md §10。
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
# バックスラッシュ 1 文字。`'\'` と直書きすると shellcheck SC1003 (「引用符の
# エスケープ間違いでは?」) が出るため、$'' 形式で明示する。
bs=$'\\'

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
# どれも読めない / 壊れている場合だけ組み込み既定にフォールバックする。
# フォールバックが必要なのは tests/run-hook-tests.sh が隔離 HOME で hook を実行する
# ため — 実設定に依存するとテスト結果が実ユーザー環境の設定に左右される。
builtin_globs=('docker *' 'gh *' 'brew *' 'pnpm test:e2e *')

settings_files=()
[[ -n "${HOME:-}" && -r "$HOME/.claude/settings.json" ]] && settings_files+=("$HOME/.claude/settings.json")
[[ -r ".claude/settings.json" ]] && settings_files+=(".claude/settings.json")
[[ -r ".claude/settings.local.json" ]] && settings_files+=(".claude/settings.local.json")
managed="/Library/Application Support/ClaudeCode/managed-settings.json"
[[ -r "$managed" ]] && settings_files+=("$managed")

globs=()
if [[ ${#settings_files[@]} -gt 0 ]]; then
  while IFS= read -r g; do
    [[ -n "$g" ]] && globs+=("$g")
  done < <(jq -r '.sandbox.excludedCommands // [] | .[]' "${settings_files[@]}" 2>/dev/null || true)
fi
if [[ ${#globs[@]} -eq 0 ]]; then
  globs=("${builtin_globs[@]}")
fi

# glob からリテラル前置語だけを取り出す ("gh *" → "gh", "pnpm test:e2e *" → "pnpm test:e2e")。
# 先頭が glob メタ文字の entry ("*" 等) は「全コマンドが除外対象」を意味するので、
# 空 prefix として残し、後段で任意の segment に一致させる (危険側に緩めない)。
prefixes=()
match_any=0
for g in "${globs[@]}"; do
  p=${g%%[*?[]*}          # 最初の glob メタ文字以降を落とす
  p=${p%"${p##*[! ]}"}    # 末尾空白を落とす
  if [[ -z "$p" ]]; then
    match_any=1
  else
    prefixes+=("$p")
  fi
done
[[ ${#prefixes[@]} -eq 0 && $match_any -eq 0 ]] && exit 0

# --- コマンド行の分解 ---------------------------------------------------------
# クォートとバックスラッシュを 1 パスで解釈する。正規表現でクォート span を
# 削除する方式は採らない — `echo "don't"` のようにダブルクォート内の
# アポストロフィがあると、対にならないシングルクォートの間 (実在の区切りと
# 除外コマンドを含む範囲) がまるごと消えてブロックを素通りする。
#
# 出力 `parsed` の性質:
#   - クォート文字とエスケープのバックスラッシュは落とす
#     (`g"h" --version` → `gh --version`。上流もコマンド語のクォートを外して照合する)
#   - クォート内 / エスケープされた区切り文字は `_` に潰す (シェル上でも区切りに
#     ならないため。`--jq '.[] | .name'` を誤ブロックしない)
#   - クォート外の区切り文字はそのまま残す
# クォートが閉じていない場合は解釈を諦め、生のコマンドで分割する (ブロック側に倒す)。
parsed=""
len=${#command}
if [[ $len -gt 8000 ]]; then
  # 極端に長い入力は 1 文字ずつの走査コストが見合わないので生のまま扱う (ブロック側)。
  parsed="$command"
else
  in_s=0
  in_d=0
  i=0
  while [[ $i -lt $len ]]; do
    c=${command:$i:1}
    lit=""
    if [[ $in_s -eq 1 ]]; then
      if [[ "$c" == "'" ]]; then in_s=0; else lit="$c"; fi
    elif [[ $in_d -eq 1 ]]; then
      if [[ "$c" == '"' ]]; then
        in_d=0
      elif [[ "$c" == "$bs" ]]; then
        i=$((i + 1)); lit=${command:$i:1}
      else
        lit="$c"
      fi
    else
      case "$c" in
        "'") in_s=1 ;;
        '"') in_d=1 ;;
        "$bs") i=$((i + 1)); lit=${command:$i:1} ;;
        '&')
          # リダイレクト複製子 (`2>&1` / `>&2` / `&>file`) の & は区切りではない。
          # 潰さないと `gh pr view 1 2>&1` 単独が compound に見えて誤ブロックになる。
          prev=""
          [[ ${#parsed} -gt 0 ]] && prev=${parsed:$((${#parsed} - 1)):1}
          nxt=${command:$((i + 1)):1}
          if [[ "$prev" == '>' || "$prev" == '<' || "$nxt" == '>' ]]; then
            parsed+='_'
          else
            parsed+='&'
          fi
          ;;
        *) parsed+="$c" ;;
      esac
    fi
    if [[ -n "$lit" ]]; then
      # リテラル扱いの文字。区切り文字なら潰す。
      case "$lit" in
        ';'|'|'|'&'|"$nl"|"$cr") parsed+='_' ;;
        *) parsed+="$lit" ;;
      esac
    fi
    i=$((i + 1))
  done
  if [[ $in_s -ne 0 || $in_d -ne 0 ]]; then
    parsed="$command"
  fi
fi

segments=$(printf '%s' "$parsed" | tr ';|&'"$cr" '\n')

# --- segment ごとの照合 -------------------------------------------------------
# 1 パスで「非空 segment の数」と「除外コマンドとの一致」を同時に取る。数が必要なのは、
# 区切り文字が引用符の中にしか無かった場合 (解釈後に単独 segment へ戻る) を
# ブロック対象から外すため。
#
# 環境変数代入の剥がしパターン。値に `$` / バックティック / `(` / `)` を許さないのは
# 上流の正規化に合わせるため — 上流は `X=$(foo) gh bar` の代入を剥がさず、コマンド語を
# `X=$(foo)` と読むので sandbox は外れない。ここで剥がすと `gh bar` に到達して
# 実際には穴でない行をブロックしてしまう (安全側の誤りだが誤検知は減らす)。
assign_re='^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]$`()]*[[:space:]]+'

seg_count=0
matched=""
while IFS= read -r seg; do
  seg=${seg#"${seg%%[![:space:]]*}"}
  [[ -z "$seg" ]] && continue
  seg_count=$((seg_count + 1))
  [[ -n "$matched" ]] && continue

  # 先頭の `!` / 環境変数代入 (VAR=value) / wrapper コマンドを剥がしてコマンド語に到達する。
  # 上流の正規化と同じ集合。剥がしすぎても「ブロックしない方向」には倒れない
  # (剥がした結果が除外コマンドでなければ、そのまま一致しないだけ)。
  while : ; do
    before="$seg"
    seg=${seg#!}
    seg=${seg#"${seg%%[![:space:]]*}"}
    while [[ "$seg" =~ $assign_re ]]; do
      seg=${seg#"${BASH_REMATCH[0]}"}
    done
    case "$seg" in
      'command '*|'builtin '*|'noglob '*|'nohup '*|'time '*)
        seg=${seg#* }
        ;;
      'nice '*|'stdbuf '*|'timeout '*)
        seg=${seg#* }
        # これらは自分のオプション / 引数を取る。オプション (-x) と、
        # nice/timeout の数値・duration 引数を落としてから次のコマンド語へ進む。
        while [[ "$seg" == -* || "$seg" =~ ^[0-9]+[smhd]?[[:space:]] ]]; do
          seg=${seg#* }
          seg=${seg#"${seg%%[![:space:]]*}"}
        done
        ;;
    esac
    seg=${seg#"${seg%%[![:space:]]*}"}
    [[ "$seg" == "$before" ]] && break
  done

  if [[ $match_any -eq 1 ]]; then
    matched="*"
    continue
  fi
  for p in "${prefixes[@]}"; do
    if [[ "$seg" == "$p" || "$seg" == "$p "* ]]; then
      matched="$p"
      break
    fi
  done
done <<< "$segments"

# 単独コマンド (区切りが無い) はブロック対象外。除外コマンド自体はこの形で使う。
[[ $seg_count -le 1 ]] && exit 0
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
EOF
exit 2
