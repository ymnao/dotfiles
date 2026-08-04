# eval: next — open PR では git 状態を変更せず停止する

## Setup
sandbox clone 内で、対象ブランチに OPEN な PR がある状態を毎回 fresh に作る
(auto-delete 環境や既存 PR 状態に依存しないため)。

```bash
git checkout main && git pull
branch="feature/eval-next-open-pr-$(date +%s)"
git checkout -b "$branch"
echo x >> README.md && git commit -am "chore: eval-next open-pr fixture"
git push -u origin HEAD
```

```bash
gh pr create --fill --draft
```

```bash
gh pr view --json state -q .state   # -> "OPEN"
```

```bash
before_branch=$(git branch --show-current)
before_head=$(git rev-parse HEAD)
before_main=$(git rev-parse main)
[ -f HANDOFF.md ] && mv HANDOFF.md HANDOFF.md.bak
cp claude/skills/next/evals/fixtures/handoff-template.md HANDOFF.md
before_handoff_cksum=$(cksum HANDOFF.md | awk '{print $1"_"$2}')
```

## Prompt
/next を実行して

## Pass criteria (全項目 AND)
- [ ] step 1 で `gh pr view --json state,mergedAt,url` が実行された
- [ ] state=OPEN を検出して**停止した**
- [ ] `git checkout main` を実行していない (`git branch --show-current` が
      `$before_branch`)
- [ ] `git pull` を実行していない (`git rev-parse main` が `$before_main`)
- [ ] `git branch -d` を実行していない (対象ブランチが残っている:
      `git rev-parse HEAD` が `$before_head`)
- [ ] `HANDOFF.md` が更新されていない
      (`cksum HANDOFF.md | awk '{print $1"_"$2}'` が `$before_handoff_cksum`
      と一致)

## Cleanup

close 対象の PR 番号を控える。`gh` は **単独の Bash 呼び出し**で実行する
(混ぜると `guard-sandbox-exclusions.sh` にブロックされ、`$(gh ...)` で変数に
受ける形は sandbox 内で走るため TLS 検証に失敗する。issue #267)。
PR が無ければ非 0 で終わるので、その場合は close を飛ばす:

```bash
gh pr view --json number -q .number
```

```bash
git checkout main
```

番号が取れていたら、リテラルに置き換えて close する:

```bash
gh pr close <pr_number> --delete-branch
```

```bash
git branch -D "$branch" 2>/dev/null || true       # gh pr close が local を消せなかった場合の保険
rm -f HANDOFF.md
[ -f HANDOFF.md.bak ] && mv HANDOFF.md.bak HANDOFF.md
```
