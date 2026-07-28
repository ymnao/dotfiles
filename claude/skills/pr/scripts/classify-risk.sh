#!/usr/bin/env bash
set -euo pipefail

# 現在のブランチの diff (base...HEAD) をリスク分類する。
#
# 使い方: classify-risk.sh <base-branch>
# 出力 (JSON): {"tier": "high|medium|low", "reasons": ["<rule>: <対象>", ...]}
# exit: 0 = 分類成功 (tier がどれでも 0) / 1 = 前提エラー
#
# 分類はモデルの判断に任せず path/grep で決定的に行う (下位モデルでも
# 同一精度にするため)。ルール追加はこのファイルの RULES セクションだけを
# 編集すればよい構造にしてある。

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is not installed" >&2
  exit 1
fi

BASE="${1:-}"
if [ -z "$BASE" ]; then
  echo "usage: classify-risk.sh <base-branch>" >&2
  exit 1
fi

# base ref 解決 (gather-branch-info.sh と同じ流儀: ローカル優先、origin/ フォールバック)
REF="$BASE"
if ! git rev-parse --verify "$BASE" >/dev/null 2>&1; then
  if git rev-parse --verify "origin/$BASE" >/dev/null 2>&1; then
    REF="origin/$BASE"
  else
    echo "ERROR: base branch '$BASE' not found locally or on origin" >&2
    exit 1
  fi
fi

# 全 file list (path check / tier=low 判定用)。改行含みパスは quote されうるが
# path rule は行単位 grep なので実害なし。--name-only の quote は名前表示問題
# だけで、実 pathspec を必要とするのは下の code_files 経路のみ
files=$(git diff "$REF...HEAD" --name-only)

# content check の除外対象: 「エージェントに指示として解釈されない」文書のみ。
# `README*.md` / `docs/` / `LICENSE*` / `.txt` / `evals/*.md` fixture。
# SKILL.md / AGENTS.md / CLAUDE.md / claude/skills/**/*.md などは
# エージェントが指示として解釈するため content check の対象に残す
# (security ゲート bypass 防止 / eval fixture 誤検知回避の両立)。
# 散文の誤検知は「ここから *.md を除外する」ではなく RULES 側のパターンを
# 実行構文に寄せて直すこと (issue #227)
NOT_EXECUTABLE_DOC_PATTERN='(^|/)README[^/]*\.md$|^docs/|(^|/)LICENSE[^/]*$|\.txt$|(^|/)evals?/[^/]*\.md$'

# code_files を pathspec 安全に取得するため -z (NUL 区切り) を使う。
# 空白・改行・非 ASCII を含むパスでも正しく pathspec 復元できる
added_code=""
paths=()
while IFS= read -r -d '' f; do
  [ -n "$f" ] || continue
  # NOT_EXECUTABLE_DOC_PATTERN にマッチするファイルは content check 対象外
  if ! printf '%s' "$f" | grep -qE "$NOT_EXECUTABLE_DOC_PATTERN"; then
    paths+=("$f")
  fi
done < <(git diff "$REF...HEAD" --name-only -z)

if [ "${#paths[@]}" -gt 0 ]; then
  # 追加行 (+++ ヘッダを除く)。バイナリ diff は git が行を出さないので無視される。
  # --literal-pathspecs で diff 由来のパスに紛れ込みうる pathspec magic
  # (`:(exclude)...` 等) を無効化し、別ファイルの content check を skip
  # させる bypass を防ぐ
  added_code=$(git --literal-pathspecs diff "$REF...HEAD" --unified=0 -- "${paths[@]}" 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' || true)
fi
# 削除されたファイル (rename は R として別扱いになるため含まれない)
deleted=$(git diff "$REF...HEAD" --name-only --diff-filter=D)

reasons=""
add_reason() {
  reasons="${reasons}${reasons:+
}$1"
}

# パスルール: 変更ファイル名が ERE にマッチしたら HIGH
check_path() {
  local rule="$1" pattern="$2" m
  m=$(printf '%s\n' "$files" | grep -iE "$pattern" | head -3 || true)
  [ -n "$m" ] && add_reason "$rule: $(printf '%s' "$m" | tr '\n' ' ')"
  return 0
}

# 内容ルール: doc-only を除くコード側ファイルの追加行が ERE にマッチしたら HIGH
check_content() {
  local rule="$1" pattern="$2" m
  m=$(printf '%s\n' "$added_code" | grep -iE "$pattern" | head -2 || true)
  [ -n "$m" ] && add_reason "$rule: $(printf '%s' "$m" | cut -c1-80 | tr '\n' ' ')"
  return 0
}

# 削除ルール: 削除されたファイル名が ERE にマッチしたら HIGH
# (エージェントが「テストを消して green にする」事故の検出。変更・追加は対象外)
check_deleted() {
  local rule="$1" pattern="$2" m
  m=$(printf '%s\n' "$deleted" | grep -iE "$pattern" | head -3 || true)
  [ -n "$m" ] && add_reason "$rule (deleted): $(printf '%s' "$m" | tr '\n' ' ')"
  return 0
}

# ---- RULES (ここだけ編集すればルールを増減できる) ----
check_path "auth-code"    '(^|/)(auth|login|session|oauth|token|secret|password|crypt|credential)[^/]*(/|$)'
check_path "ci-config"    '^\.github/workflows/|Jenkinsfile|\.gitlab-ci|^\.circleci/'
check_path "dependency"   'package\.json$|package-lock\.json$|pnpm-lock\.yaml$|yarn\.lock$|bun\.lockb?$|pyproject\.toml$|uv\.lock$|poetry\.lock$|requirements[^/]*\.txt$|go\.(mod|sum)$|Cargo\.(toml|lock)$|Gemfile(\.lock)?$|Brewfile$'
check_path "agent-config" 'settings[^/]*\.json$|(^|/)hooks/|hooks\.json$|AGENTS\.md$|CLAUDE\.md$|\.mcp\.json$'
check_path "env-files"    '(^|/)\.env|\.npmrc$|config\.toml$'
check_path "infra"        'Dockerfile|docker-compose|\.tf$|\.tfvars$'
# exec-pattern の `eval` は、シェルの実行構文として読める形だけを検出する
# (issue #227)。散文中の「eval」の語では発火させないが、実行形を取りこぼすと
# `.md` 単独 diff は tier=low = 無レビューになるため、FN は FP より高くつく。
# 3 経路の OR で、どれか 1 つでも当たれば検出する:
#   ADJACENT — eval から展開・引用文字までが、シェルの語として解釈できる
#     ASCII トークンだけで繋がっている形。`run: eval "$x"` のように行の途中に
#     前置がある実行指示形を拾うのが役割 (位置に依存しない)
#   CMDPOS — eval がシェルのコマンド位置 (行頭 / `;` `&` `||` の直後 /
#     `then` `do` `else` `elif` の直後) にあり、
#     同じ行のどこかに展開・引用文字がある形。ADJACENT の語クラスは allow-list
#     なので `[` `\` `>` `,` や多バイトを 1 文字挟むだけで越えられる
#     (`eval arr[$i]=$X` `eval value=\$$name` `eval 2>/dev/null "$x"`)。
#     位置を固定する代わりに間の文字種を問わないことでその穴を塞ぐ
#   LINECONT — 行末が `eval \` の形。引数が次行にあるため grep の行単位
#     マッチでは中身を見られないので、この形自体を検出対象にする
# 位置集合に入れないもの (いずれも repo 実測で FP になった):
#   `(` — 日本語の丸括弧 (`(eval が ...`) が散文で頻出する。このため
#         `(eval arr[$i]=$X)` のような subshell 直後の形は取りこぼす
#         (`(eval "$x")` は ADJACENT が拾う)
#   バッククォート — Markdown のインラインコード (`` `eval ls -la` ``)
#   単独の `|` — Markdown のテーブル行 (`| eval | ... | `$x` |`)。
#         `||` の 2 文字を要求すればテーブルと分離できるので `||` は入れている
# 既知の非検出: 展開も引用も一切含まない静的リテラルの `eval ls -la`
# (動的展開が無く、このルールが見ているリスクに当たらないため意図的)。
# 実測 (tracked 行に `+` を前置した added_code 相当のコーパスに対するマッチ
# ファイル数): 旧 `eval ` = 58 / ADJACENT のみ = 5 / 現行の 3 経路 = 5。
# 手で組んだ検体では危険形 20 種を 20 件とも検出、散文 11 種は 0 件検出。
# 3 経路それぞれの検出責務は mutation check で確認済み (経路を 1 つ落とすと
# tests/classify-risk の対応ケースが FAIL する)。
# なお下の例示コメント自身がこのパターンにマッチするため、このファイルを触る
# PR は tier=high になる。実行構文の具体例を残す方を優先した意図的な結果で、
# 自ファイル除外は入れない (除外は bypass 経路になる)。
EVAL_WORD='[-A-Za-z0-9_./=]'      # eval の引数の語として許す文字集合
EVAL_Q='["$`'"'"']'               # 展開・引用の開始文字 (" $ backquote ')
EVAL_ADJACENT="eval([[:space:]]+${EVAL_WORD}+)*[[:space:]]+(${EVAL_WORD}*[=_])?${EVAL_Q}"
EVAL_CMDPOS="(^\\+|[;&]|\\|\\||(^|[^A-Za-z0-9_])(then|do|else|elif)[[:space:]])[[:space:]]*eval[[:space:]].*${EVAL_Q}"
EVAL_LINECONT='eval[[:space:]]*\\$'
check_content "exec-pattern"        "${EVAL_ADJACENT}|${EVAL_CMDPOS}|${EVAL_LINECONT}|child_process|subprocess|os\\.system|exec\\(|dangerouslySetInnerHTML"
check_content "pipe-to-shell"       '(curl|wget)[^|;]*\|[[:space:]]*(ba|z|da)?sh'
check_content "permission-widening" 'chmod (777|666)|--dangerously|--no-verify'
check_deleted "test-removal" '(^|/)(tests?|__tests__|spec)/|\.(test|spec)\.[a-z]+$|_test\.(go|py|rb|ts|tsx|js|jsx)$|\.cases\.jsonl$'
# 全 diff がこのパターンにマッチする文書だけなら tier=low に落とす
# (content check の除外パターン NOT_EXECUTABLE_DOC_PATTERN より広い —
# 危険文字列がない SKILL.md/CLAUDE.md の tweak も low 扱いにするため)
LOW_ONLY_PATTERN='\.md$|^docs/|^LICENSE|\.txt$'
# ---- /RULES ----

tier="medium"
if [ -n "$reasons" ]; then
  tier="high"
elif [ -n "$files" ] && [ -z "$(printf '%s\n' "$files" | grep -ivE "$LOW_ONLY_PATTERN" || true)" ]; then
  tier="low"
  add_reason "low-only: 変更がドキュメント類のみ"
fi

jq -n --arg tier "$tier" --arg reasons "$reasons" \
  '{tier: $tier, reasons: ($reasons | split("\n") | map(select(length > 0)))}'
