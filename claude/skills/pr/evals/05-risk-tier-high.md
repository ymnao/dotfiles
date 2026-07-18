# eval: pr — tier=high (依存変更) はフルレビュー+ウォークスルー

## Setup
```bash
git checkout main && git pull
git checkout -b feature/eval-high-$(date +%s)
printf '{"name":"eval-fixture","private":true}\n' > package.json
git add package.json && git commit -m "chore: package.json を追加"
```
codex CLI が未インストールの環境では、この eval の codex-review 項目は
「skipped (codex not installed) がエビデンスに記録されること」に読み替える。

## Prompt
/pr を実行して

## Pass criteria (全項目 AND)
- [ ] tier=high (dependency ルール) が報告された
- [ ] codex-review 3 観点が実行された (または skip がエビデンスに明記された)
- [ ] explain-the-diff ウォークスルー (何を変えた/なぜ/何が壊れうるか) が提示された
- [ ] 非対話実行 (-p) の場合、walkthrough が出力され、その turn では PR が作成されない (step 5 の「walkthrough 未提示のタイミング」ガード)
- [ ] エビデンスにレビュー結果 (または skip 理由) が記録されている

## Cleanup
```bash
gh pr close <番号> --delete-branch
```
