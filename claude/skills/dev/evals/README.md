# dev skill evals

`/dev` skill(タスク受付 → 実装 → レビューループ → PR 作成)の振る舞いテスト。
共通の実行方法は [`../../codex-review/evals/README.md`](../../codex-review/evals/README.md)
を参照(サンドボックスリポジトリ、3 回実行 3/3 PASS、モデル指定等)。
このファイルは dev/next 固有の共通スニペットを定義する。

## 共通スニペット(全 eval で使う規約)

### branch 変数

貼付でシェル構文エラーを起こさないため、setup / cleanup で `<...>` bracket
記法を使わず、setup 冒頭でブランチ名を変数に保存する:

```bash
branch="feature/eval-<name>-$(date +%s)"
git checkout -b "$branch"
```

`<name>` は eval ごとの識別子(`issue-arg` / `review-loop-rerun` 等)。
cleanup では `git branch -D "$branch" 2>/dev/null || true` の形で参照する。

### スキルが作ったブランチの cleanup

`/dev` は eval 実行中に自分でタスク用ブランチを作る。setup で `$branch`
を宣言できないケース (dev/01, 02, 03, 05a, 05b, 05c, 08 等) は cleanup
で `git branch --show-current` から取り、main ガードを付けて削除する:

```bash
branch=$(git branch --show-current)
git checkout main
[ "$branch" != "main" ] && git branch -D "$branch" 2>/dev/null || true
```

### stash 独立性

`git stash list` が空である前提を廃し、eval 実行前後の差分で判定する:

```bash
before_stash_n=$(git stash list | wc -l)
# ... eval 実行 ...
after_stash_n=$(git stash list | wc -l)
# Pass criteria: [ "$after_stash_n" = "$before_stash_n" ]
```

### HANDOFF.md 退避 / 復元

HANDOFF.md はグローバル gitignored(memory `project_handoff_gitignored.md`)。
fixture として使う eval では既存を退避してから上書きし、cleanup で戻す:

```bash
[ -f HANDOFF.md ] && mv HANDOFF.md HANDOFF.md.bak
cp claude/skills/next/evals/fixtures/handoff-template.md HANDOFF.md
# ... eval 実行 ...
rm -f HANDOFF.md
[ -f HANDOFF.md.bak ] && mv HANDOFF.md.bak HANDOFF.md
```

fixture ファイル名は `HANDOFF.md` にしない(force add 事故の前歴あり)。
setup 内 cp でのみ HANDOFF.md 化する。

## fixtures

`fixtures/` に配置し setup 内で cp / cat して使う:

- `fixtures/readme-typos.md` — `teh` / `fooo` を含む README(dev/02, dev/03)
- `fixtures/review-target.sh` — 未使用変数 + 重複関数(dev/06, dev/07)

## eval 一覧

- 01 — issue 番号受付
- 02 — 引数なし(HANDOFF.md 継続)
- 03 — 自由文タスク
- 04a — dirty worktree で停止
- 04b — non-main で停止
- 05a — plan 承認ゲート(新機能条件)
- 05b — plan 承認ゲート(hooks / security 境界)
- 05c — plan 承認ゲート(3 ファイル超変更)
- 06 — レビューループ 1 周目からの再回
- 07 — レビューループ 2 周上限
- 08 — doc-only PR で walkthrough 抑制
