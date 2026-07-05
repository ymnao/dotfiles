# eval: codex-review — クリーンな diff は全観点 PASS

## Setup
sandbox clone 内で:
```bash
git checkout main && git pull
git checkout -b feature/eval-clean-$(date +%s)
printf '# note\n' >> README.md
git commit -am "docs: note を追記"
```
codex CLI がインストールされていること (なければこの eval は SKIP と記録)。

## Prompt
/codex-review を実行して

## Pass criteria (全項目 AND)
- [ ] 3 観点すべて実行された
- [ ] 全観点 PASS (findings 0) の表が報告された
- [ ] working tree に修正が加えられていない (`git status --porcelain` が空)
- [ ] コミットしていない

## Cleanup
```bash
git checkout main && git branch -D <ブランチ>
```
