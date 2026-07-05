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
# 追加行のみ (+++ ヘッダを除く)。バイナリ diff は git が行を出さないので自然に無視される
added=$(git diff "$REF...HEAD" --unified=0 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' || true)

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

# 内容ルール: 追加行が ERE にマッチしたら HIGH
check_content() {
  local rule="$1" pattern="$2" m
  m=$(printf '%s\n' "$added" | grep -iE "$pattern" | head -2 || true)
  [ -n "$m" ] && add_reason "$rule: $(printf '%s' "$m" | cut -c1-80 | tr '\n' ' ')"
  return 0
}

# ---- RULES (ここだけ編集すればルールを増減できる) ----
check_path "auth-code"    '(^|/)(auth|login|session|oauth|token|secret|password|crypt|credential)[^/]*(/|$)'
check_path "ci-config"    '^\.github/workflows/|Jenkinsfile|\.gitlab-ci|^\.circleci/'
check_path "dependency"   'package\.json$|package-lock\.json$|pnpm-lock\.yaml$|yarn\.lock$|bun\.lockb$|pyproject\.toml$|uv\.lock$|requirements[^/]*\.txt$|go\.(mod|sum)$|Cargo\.(toml|lock)$|Gemfile(\.lock)?$|Brewfile$'
check_path "agent-config" 'settings[^/]*\.json$|(^|/)hooks/|hooks\.json$|AGENTS\.md$|CLAUDE\.md$|\.mcp\.json$'
check_path "env-files"    '(^|/)\.env|\.npmrc$|config\.toml$'
check_path "infra"        'Dockerfile|docker-compose|\.tf$|\.tfvars$'
check_content "exec-pattern"        'eval |child_process|subprocess|os\.system|exec\(|dangerouslySetInnerHTML'
check_content "pipe-to-shell"       '(curl|wget)[^|;]*\|[[:space:]]*(ba|z|da)?sh'
check_content "permission-widening" 'chmod (777|666)|--dangerously|--no-verify'
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
