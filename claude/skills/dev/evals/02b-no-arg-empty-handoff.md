# eval: dev — 引数なし (HANDOFF.md が空 / 曖昧) → 停止

## Setup
sandbox clone 内で main、clean tree にする。既存 HANDOFF.md は退避し、
検証したいケースに応じて空 or 「TBD」のみの HANDOFF.md を配置する。
HANDOFF.md はグローバル gitignored なのでコミットされない。

共通 (先頭):

```bash
git checkout main && git pull
handoff_backup=$(mktemp)
[ -f HANDOFF.md ] && mv HANDOFF.md "$handoff_backup"
```

Case 別に HANDOFF.md を生成:

- **Case A (空 HANDOFF)**: `: > HANDOFF.md`
- **Case B (曖昧 HANDOFF)**: `printf '# HANDOFF\n\nTBD\n' > HANDOFF.md`

共通 (Case 生成後):

```bash
before_handoff_cksum=$(cksum HANDOFF.md)
before_head=$(git rev-parse HEAD)
```

いずれのケースも `git status --porcelain` は空 (HANDOFF.md は gitignored)。

## Prompt
/dev を実行して

## Pass criteria (全項目 AND)

機械検証可能:
- [ ] `git branch --show-current` が `main` のまま (新ブランチを作らずに停止)
- [ ] `git rev-parse HEAD` が `$before_head` と一致 (新規コミット 0)
- [ ] `cksum HANDOFF.md` が `$before_handoff_cksum` と一致 (HANDOFF.md 不変)
- [ ] `gh pr list --head "$(git branch --show-current)" --json number` が空
      (PR を作っていない)
- [ ] `git check-ignore HANDOFF.md` がヒットする (gitignored 確認)

transcript 判定 (human runner):
- [ ] `/dev` が「HANDOFF.md が空 / 曖昧である」旨を認識した発言をした
- [ ] user にタスク内容 (次にやること) を問う質問で応答を終了している
- [ ] transcript に実装行為 (Edit / Write / branch 作成 / commit) が
      **一切ない** (SKILL.md step 1「勝手に stash / checkout しない」準拠)

## Cleanup
```bash
rm -f HANDOFF.md
[ -s "$handoff_backup" ] && mv "$handoff_backup" HANDOFF.md || rm -f "$handoff_backup"
```

(HANDOFF.md 継続経路の happy path は `02-no-arg-handoff.md` を参照。
本 eval は「停止すべき経路」だけを検証する。)
