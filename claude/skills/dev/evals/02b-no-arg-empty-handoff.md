# eval: dev — 引数なし (HANDOFF.md が空) → 停止

## Setup
sandbox clone 内で main、clean tree にする。既存 HANDOFF.md は退避し、
空 HANDOFF.md を配置する。HANDOFF.md はグローバル gitignored 前提だが、
環境非依存化のため setup で `.git/info/exclude` にも追加する
(README の [HANDOFF.md gitignore を repo-local に強制する](README.md#handoff-local-ignore)
節参照)。

`git pull` は使わない (README の
[setup で `git pull` を実行しない](README.md#no-git-pull) 節参照)。

```bash
git checkout main
handoff_backup=$(mktemp)
[ -f HANDOFF.md ] && mv HANDOFF.md "$handoff_backup"

exclude_backup=$(mktemp)
cp .git/info/exclude "$exclude_backup"
grep -qxF 'HANDOFF.md' .git/info/exclude || echo 'HANDOFF.md' >> .git/info/exclude

: > HANDOFF.md
git check-ignore HANDOFF.md >/dev/null || { echo "SKIP: HANDOFF.md not ignored"; exit 77; }

before_head=$(git rev-parse HEAD)
before_prs=$(gh pr list --state all --limit 1000 --json number -q '.[].number' | sort -u)
```

`git status --porcelain` は空 (HANDOFF.md は gitignored)。

## Prompt
/dev を実行して

## Pass criteria (全項目 AND)

機械検証可能:
- [ ] `git branch --show-current` が `main` のまま (新ブランチを作らずに停止)
- [ ] `git rev-parse HEAD` が `$before_head` と一致 (新規コミット 0)
- [ ] `[ ! -s HANDOFF.md ]` (HANDOFF.md が空のまま = 追記されていない)
- [ ] `gh pr list --state all --limit 1000 --json number -q '.[].number' | sort -u`
      が `$before_prs` と一致 (PR を作っていない。README
      [PR 非作成の検証パターン](README.md#pr-not-created-check) 参照)

transcript 判定 (human runner):
- [ ] `/dev` が「HANDOFF.md が空である」旨を認識した発言をした
- [ ] user にタスク内容 (次にやること) を問う質問で応答を終了している
- [ ] transcript に実装行為 (Edit / Write / branch 作成 / commit /
      `gh pr create`) が **一切ない** (SKILL.md step 1「勝手に stash /
      checkout しない」準拠)

## Cleanup
```bash
rm -f HANDOFF.md
[ -f "$handoff_backup" ] && mv "$handoff_backup" HANDOFF.md || rm -f "$handoff_backup"
mv "$exclude_backup" .git/info/exclude
```

(HANDOFF.md 継続経路の happy path は `02-no-arg-handoff.md` を、
「TBD のみの曖昧 HANDOFF」経路は `02c-no-arg-stub-handoff.md` を参照。
本 eval は「空 HANDOFF で停止すべき経路」だけを検証する。)
