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

files=$(git diff "$REF...HEAD" --name-only)
# doc-only ファイル (LOW_ONLY_PATTERN と同一定義) を除いたコード側パス。
# content check はこの subset の追加行のみを対象にする。eval fixture の
# shell スニペットが exec-pattern として拾われる誤検知を防ぐため
LOW_ONLY_PATTERN='\.md$|^docs/|^LICENSE|\.txt$'
code_files=$(printf '%s\n' "$files" | grep -vE "$LOW_ONLY_PATTERN" || true)
# 追加行 (+++ ヘッダを除く)。content check には code_files に絞った added_code
# を渡し、path check 用の added はレガシー互換のため残す (現状 path check は
# added を使わない)。バイナリ diff は git が行を出さないので自然に無視される
added_code=""
if [ -n "$code_files" ]; then
  # xargs -r は BSD 非対応。空リスト時は `git diff -- <no paths>` が
  # 全 diff にフォールバックしてしまうため、空判定を先に済ませてから
  # bash 配列で pathspec を安全に渡す (空白入りパス・shell メタ文字対応)
  paths=()
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    paths+=("$f")
  done <<EOF
$code_files
EOF
  if [ "${#paths[@]}" -gt 0 ]; then
    added_code=$(git diff "$REF...HEAD" --unified=0 -- "${paths[@]}" 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' || true)
  fi
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
check_content "exec-pattern"        'eval |child_process|subprocess|os\.system|exec\(|dangerouslySetInnerHTML'
check_content "pipe-to-shell"       '(curl|wget)[^|;]*\|[[:space:]]*(ba|z|da)?sh'
check_content "permission-widening" 'chmod (777|666)|--dangerously|--no-verify'
check_deleted "test-removal" '(^|/)(tests?|__tests__|spec)/|\.(test|spec)\.[a-z]+$|_test\.(go|py|rb|ts|tsx|js|jsx)$|\.cases\.jsonl$'
# LOW_ONLY_PATTERN は content check 絞り込みのため上部で定義済み
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
