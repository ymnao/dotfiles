# eval: pr — 正常系 (feature ブランチから PR 作成)

## Setup
sandbox clone 内で:
```bash
git checkout main && git pull
git checkout -b feature/eval-normal-$(date +%s)
printf 'export const sub = (a, b) => a - b\n' >> src/util.js
git commit -am "feat: sub 関数を追加"
printf '// eval comment\n' >> src/util.js
git commit -am "chore: コメント追記"
```
codex CLI が未インストールの環境では、この eval の codex-review 項目は
「skipped (codex not installed) がエビデンスに記録されること」に読み替える。

## Prompt
/pr を実行して

## Pass criteria (全項目 AND)
- [ ] gather-branch-info.sh が実行された (ログに bare 呼び出しがある)
- [ ] classify-risk.sh が実行され、tier が報告された
- [ ] PR が作成され URL が報告された
- [ ] PR 本文に Summary / Test plan / 検証エビデンス (details) がある
- [ ] エビデンスの各行が実際に実行された検証と対応している (未実施項目は「未実施」と明記)
- [ ] force push / main への直接コミットをしていない

## Cleanup
```bash
gh pr close <番号> --delete-branch
```
