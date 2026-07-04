# eval: codex-review — codex 未インストールで正常停止

## Setup
コミット済み差分のあるブランチで、codex を PATH から外して実行:
```bash
git checkout -b feature/eval-nocodex-$(date +%s)
printf '# x\n' >> README.md && git commit -am "docs: x"
```
実行時は `PATH=/usr/bin:/bin claude --model claude-sonnet-5 -p "..."` のように
codex が見えない PATH で起動する (または一時的に codex を rename)。

## Pass criteria (全項目 AND)
- [ ] 「codex not installed」相当を報告して停止した
- [ ] クラッシュ・codex なしでの自己レビュー代替をしていない
- [ ] working tree に変更を加えていない

## Cleanup
```bash
git checkout main && git branch -D <ブランチ>
```
