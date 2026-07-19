# eval: dev — 引数なし (HANDOFF.md が曖昧 = TBD のみ) → 停止

## Setup
sandbox clone 内で main、clean tree にする。既存 HANDOFF.md は退避し、
`# HANDOFF` + `TBD` のみの stub HANDOFF.md を配置する。setup / cleanup
の共通手順は 02b と同じ (README の
[HANDOFF.md gitignore を repo-local に強制する](README.md#handoff-local-ignore)
と [setup で `git pull` を実行しない](README.md#no-git-pull) 参照)。

```bash
git checkout main
handoff_backup=""
if [ -f HANDOFF.md ]; then
    handoff_backup=$(mktemp)
    mv HANDOFF.md "$handoff_backup"
fi

exclude_backup=$(mktemp)
cp .git/info/exclude "$exclude_backup"
grep -qxF 'HANDOFF.md' .git/info/exclude || echo 'HANDOFF.md' >> .git/info/exclude

printf '# HANDOFF\n\nTBD\n' > HANDOFF.md
git check-ignore HANDOFF.md >/dev/null || { echo "SKIP: HANDOFF.md not ignored"; exit 77; }

before_handoff_cksum=$(cksum HANDOFF.md)
before_head=$(git rev-parse HEAD)
before_prs=$(gh pr list --state all --limit 1000 --json number -q '.[].number' | sort -u)
```

## Prompt
/dev を実行して

## Pass criteria (全項目 AND)

機械検証可能:
- [ ] `git branch --show-current` が `main` のまま
- [ ] `git rev-parse HEAD` が `$before_head` と一致
- [ ] `cksum HANDOFF.md` が `$before_handoff_cksum` と一致
- [ ] `gh pr list --state all --limit 1000 --json number -q '.[].number' | sort -u`
      が `$before_prs` と一致 (README
      [PR 非作成の検証パターン](README.md#pr-not-created-check) 参照)

transcript 判定 (human runner):
- [ ] `/dev` が「HANDOFF.md の残タスクが曖昧である (TBD のみ)」旨を
      認識した発言をした (**TBD を実タスクとみなして着手していない**)
- [ ] user にタスク内容 (次にやること) を問う質問で応答を終了している
- [ ] transcript に実装行為 (Edit / Write / branch 作成 / commit /
      `gh pr create`) が **一切ない**

## Cleanup
```bash
rm -f HANDOFF.md
[ -n "$handoff_backup" ] && mv "$handoff_backup" HANDOFF.md
mv "$exclude_backup" .git/info/exclude
```

(空 HANDOFF 経路は `02b-no-arg-empty-handoff.md`、happy path は
`02-no-arg-handoff.md` を参照。本 eval は「曖昧な残タスクで停止すべき
経路」だけを検証する。)
