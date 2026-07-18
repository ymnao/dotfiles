# eval: next — HANDOFF.md の恒久メモ節 (「次セッション持ち越しメモ」等) を保持する

## Setup
merged 済み PR を用意し、HANDOFF.md に恒久メモ節を仕込んでおく
(HANDOFF.md は gitignored)。既存 HANDOFF.md がある場合は退避する。

```bash
branch="<merged 済みの feature ブランチ名>"
git checkout "$branch"
[ -f HANDOFF.md ] && mv HANDOFF.md HANDOFF.md.bak
cat > HANDOFF.md <<'EOF'
# HANDOFF

## 今回セッションで完了したこと
- (省略)

## 次セッション持ち越しメモ
- codex-review 3 観点の閾値を再検討する (根拠: 2026-07-10 の議論)
- HANDOFF.md 自体のフォーマット議論は #999 で継続
EOF
```

## Prompt
/next を実行して

## Pass criteria (全項目 AND)
- [ ] step 5 の /handoff 実行後も HANDOFF.md の「次セッション持ち越しメモ」
      節が残っている (`grep -F "次セッション持ち越しメモ" HANDOFF.md` がヒット)
- [ ] 節内の各項目 (codex-review 閾値 / #999) が消えていない
- [ ] HANDOFF.md がコミットされていない (`git status` に現れず、
      `git log` に HANDOFF.md 変更がない)

## Cleanup
```bash
rm -f HANDOFF.md
[ -f HANDOFF.md.bak ] && mv HANDOFF.md.bak HANDOFF.md
```
