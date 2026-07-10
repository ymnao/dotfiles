#!/usr/bin/env bash
set -euo pipefail

# Stop hook 用の高速検証ゲート (make gate 経由で .claude/stop-gate.conf から呼ばれる)。
#
# 方針: フル検証 (`make test` = shellcheck 全件 + hook コーパス常時) は PR 前の
# フロー (pr skill / verify-ci) が担う。ターン終了ごとに走るこのゲートは:
#   - 軽量テスト群 (計 5〜10 秒) は常時実行
#   - 重い hook 回帰コーパス (約 35 秒) は hook 関連ファイルが dirty のときだけ実行
#   - shellcheck / JSON 検証は dirty なファイルだけを対象にする
#
# 依存: jq / git。shellcheck は無ければスキップ (フル検証は make test 側で担保)。

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# 変更ファイル一覧 (staged + unstaged + untracked)。rename 行 (R old -> new) は
# 最終フィールド = 新パスを使う。
changed=$(git status --porcelain | awk '{print $NF}')

# 1) dirty な *.sh のみ shellcheck (symlink は実体側で検査されるため除外)
if command -v shellcheck >/dev/null 2>&1; then
  sh_targets=""
  for f in $changed; do
    case "$f" in
      *.sh) [ -f "$f" ] && [ ! -L "$f" ] && sh_targets="$sh_targets $f" ;;
    esac
  done
  if [ -n "$sh_targets" ]; then
    echo "==> shellcheck (changed files)"
    # shellcheck disable=SC2086  # 意図的な word splitting (パスに空白を含まない前提のリポ)
    shellcheck -S warning $sh_targets
  fi
else
  echo "NOTE: shellcheck 未導入のためスキップ (make test では必須)"
fi

# 2) dirty な *.json のみ検証
for f in $changed; do
  case "$f" in
    *.json)
      [ -f "$f" ] || continue
      jq empty "$f" >/dev/null || { echo "FAIL: invalid JSON: $f"; exit 1; }
      ;;
  esac
done

# 3) 軽量テスト群 (常時)
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

# 4) hook 関連が dirty のときだけ重いコーパスを実行
run_corpus=0
for f in $changed; do
  case "$f" in
    agents/hooks/*|claude/hooks/*|codex/hooks/*|tests/hooks/*|tests/run-hook-tests.sh)
      run_corpus=1
      ;;
  esac
done
if [ "$run_corpus" = 1 ]; then
  echo "==> hook regression corpus (hook files changed)"
  bash tests/run-hook-tests.sh
fi

echo "OK: gate passed"
