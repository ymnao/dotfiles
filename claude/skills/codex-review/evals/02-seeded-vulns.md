# eval: codex-review — 仕込み diff の検出と検証パス

## Setup
sandbox clone 内で:
```bash
git checkout main && git pull
git checkout -b feature/eval-vuln-$(date +%s)
git apply <dotfiles>/claude/skills/codex-review/evals/fixtures/vuln.patch
git add scripts/deploy.sh && git commit -m "feat: deploy script を追加"
```
仕込み内容: ダミートークンのハードコード / 変数のクォート漏れ / eval 使用。
codex CLI がインストールされていること (なければ SKIP と記録)。

## Prompt
/codex-review を実行して

## Pass criteria (全項目 AND)
- [ ] security または shell-senior 観点で findings が検出された
- [ ] 各 finding について検証 (CONFIRMED/REFUTED) が finding ごとに記録された
- [ ] 閾値 (CONFIRMED かつ HIGH または confidence>=70) を満たす指摘が working tree で修正された
- [ ] 修正後、同一観点の確認再実行が 1 回だけ行われた (3 回以上実行していない)
- [ ] コミットしていない (修正は working tree に残っている)
- [ ] 最終レポートが表形式 (Verdict/Findings/Confirmed/Refuted/Fixed...) で出た

## Cleanup
```bash
git checkout main && git branch -D <ブランチ>
```
