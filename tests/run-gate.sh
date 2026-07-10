#!/usr/bin/env bash
set -euo pipefail

# Stop hook 用の高速検証ゲート (make gate 経由で .claude/stop-gate.conf から呼ばれる)。
#
# 方針: フル検証 (`make test` = shellcheck 全件 + hook コーパス常時) は PR 前の
# フロー (pr skill / verify-ci) が担う。ターン終了ごとに走るこのゲートは:
#   - 軽量テスト群 (計 5〜10 秒) は常時実行
#   - 重い hook 回帰コーパス (約 35 秒) は hook 関連ファイルが dirty のときだけ実行
#   - shellcheck / JSON 検証は変更 (作業ツリー dirty + ベースブランチ以降の commit) の対象ファイルだけ
#
# 依存: jq / git。shellcheck は無ければスキップ (フル検証は make test 側で担保)。

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# 変更ファイル一覧を NUL 区切りで array に集める。
# - `git status --porcelain=v1 -z -uall`: NUL 終端・quote 無し・未追跡ディレクトリは配下ファイル単位に展開
# - `core.quotePath=false`: 非 ASCII パスの octal escape を抑止し case マッチを正しく機能させる
# - rename/copy (R/C) は "XY new\0old" の 2 エントリで来るため old 側もペア追加。
#   worktree Y 列は rename/copy にならず X 列 (index) のみで発生するため `R?|C?` で十分
# - ベースブランチ (origin/main → main → origin/master → master) 以降で commit 済みの
#   変更もスコープに含める。ターン中に commit された hook 変更が corpus トリガから
#   漏れる問題への対応
changed_paths=()

base_ref=""
for ref in origin/main main origin/master master; do
  if git rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
    base_ref="$ref"
    break
  fi
done
if [ -n "$base_ref" ]; then
  while IFS= read -r -d '' p; do
    changed_paths+=("$p")
  done < <(git -c core.quotePath=false diff --name-only -z "$base_ref"...HEAD)
fi

while IFS= read -r -d '' entry; do
  changed_paths+=("${entry:3}")
  case "${entry:0:2}" in
    R?|C?)
      if IFS= read -r -d '' oldpath; then
        changed_paths+=("$oldpath")
      fi
      ;;
  esac
done < <(git -c core.quotePath=false status --porcelain=v1 -z -uall)

# 変更ファイルを 1 パスで走査し (a) shellcheck 対象収集 (b) JSON 検証
# (c) hook corpus トリガ判定 の 3 用途に振り分ける。
# bash 3.2 の set -u では空 array の "${arr[@]}" が unbound エラーになるため
# 長さ 0 なら走査自体をスキップする。
sh_targets=()
run_corpus=0
if [ "${#changed_paths[@]}" -gt 0 ]; then
  for f in "${changed_paths[@]}"; do
    case "$f" in
      *.sh)
        if [ -f "$f" ] && [ ! -L "$f" ]; then
          sh_targets+=("$f")
        fi
        ;;
      *.json)
        if [ -f "$f" ]; then
          jq empty "$f" >/dev/null || { echo "FAIL: invalid JSON: $f"; exit 1; }
        fi
        ;;
    esac
    case "$f" in
      agents/hooks/*|claude/hooks/*|codex/hooks/*|tests/hooks/*|tests/run-hook-tests.sh)
        run_corpus=1
        ;;
    esac
  done
fi

# 1) 変更対象の *.sh のみ shellcheck (symlink は実体側で検査されるため除外済み)
if command -v shellcheck >/dev/null 2>&1; then
  if [ "${#sh_targets[@]}" -gt 0 ]; then
    echo "==> shellcheck (changed files)"
    shellcheck -S warning "${sh_targets[@]}"
  fi
else
  echo "NOTE: shellcheck 未導入のためスキップ (make test では必須)"
fi

# 2) 軽量テスト群 (常時)
bash tests/parse-review-output/run-parser-tests.sh
bash tests/classify-risk/run-classify-risk-tests.sh
bash tests/agents-md-sync/run-agents-md-sync-check.sh
bash tests/statusline/run-statusline-tests.sh
bash tests/stop-verify-gate/run-stop-gate-tests.sh
bash tests/post-format/run-post-format-tests.sh
bash tests/link-backup/run-link-backup-tests.sh
# 以下は導入済みの場合のみ (PR14 / PR19 / PR22 / PR23 で追加されるテスト・検査)
[ -f tests/hooks-glob/run-glob-determinism-tests.sh ] && bash tests/hooks-glob/run-glob-determinism-tests.sh
[ -f tests/verify-ci/run-verify-ci-tests.sh ] && bash tests/verify-ci/run-verify-ci-tests.sh
[ -f tests/integrity/run-integrity-check.sh ] && bash tests/integrity/run-integrity-check.sh
[ -f tests/session-compact/run-session-compact-tests.sh ] && bash tests/session-compact/run-session-compact-tests.sh

# 3) hook 関連ファイルが変更されているときだけ重いコーパスを実行
if [ "$run_corpus" = 1 ]; then
  echo "==> hook regression corpus (hook files changed)"
  bash tests/run-hook-tests.sh
fi

echo "OK: gate passed"
