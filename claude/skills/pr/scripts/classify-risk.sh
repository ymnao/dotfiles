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
# exec-pattern の `eval` は「eval から展開・引用文字までが、シェルの語として
# 解釈できる ASCII トークンだけで繋がっている」場合に検出する (issue #227)。
# ERE の読み方 (3 パート):
#   1. ([[:space:]]+[-A-Za-z0-9_./=]+)*  … 間に挟まる語 (`bash` `-c` `--` `env` 等)
#   2. [[:space:]]+([-A-Za-z0-9_./=]*[=_])?  … 展開文字の直前に付く接頭辞。
#      `=` か `_` で終わる形だけ許す (`name=$X` `cmd_$X` を拾い、`"eval fixture"`
#      のような文字列リテラル中の語では発火させないため)
#   3. ["$`'"'"']  … 展開・引用の開始文字。`"` `$` バッククォート `'` の 4 文字
#      (`'` を含めるためシェル側で '"'"' 連結している)
# 却下した案と理由:
# - 直後を問わない形 (末尾スペースだけの `eval`): SKILL.md 等の日本語散文
#   (「skill / eval / hook」「集計スクリプトや eval を足したく」) に誤マッチし、
#   実行系を変えない PR が tier=high に落ちる。実測でマッチ 58 ファイル → 5 ファイル
# - パート 1 の語を `[^[:space:]]+` に緩める: 散文の語も語として繋がるため
#   FP が 8 行復活する (実測)
# - パート 2 の `[=_]` 終端を外す: `--body "eval fixture"` のような文字列
#   リテラル中の語で FP が復活する (実測 4 行)
# - 位置 (行頭・`;` の直後等) で絞る: added_code の各行は diff の `+` が
#   前置されており、`run: eval "$x"` のような前置つきの実行指示形を取りこぼす
# 既知の非検出: 展開も引用も含まない静的リテラルの `eval ls -la`
# (動的展開が無く、このルールが見ているリスクに当たらないため意図的)。
# なお上の `run: eval "$x"` 等の例はこのパターン自身にマッチするため、この
# ファイルを触る PR は tier=high になる。実行構文の具体例を残す方を優先した
# 意図的な結果で、自ファイル除外は入れない (除外は bypass 経路になる)
check_content "exec-pattern"        'eval([[:space:]]+[-A-Za-z0-9_./=]+)*[[:space:]]+([-A-Za-z0-9_./=]*[=_])?["$`'"'"']|child_process|subprocess|os\.system|exec\(|dangerouslySetInnerHTML'
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
