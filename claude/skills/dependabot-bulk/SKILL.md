---
name: dependabot-bulk
description: Consolidate open Dependabot PRs into one integration branch to compress CI runs from N to 1
---

open な Dependabot PR を 1 branch に統合し、push を 1 回にして CI 実行を N 回 → 原則 1 回に圧縮する。個別 PR ごとに `.github/workflows/test.yml` (push トリガー) が走ることによる GitHub Actions 分数の消費を抑える。

**前提**: `.github/dependabot.yml` に `groups: { all: { patterns: ["*"] } }` (companion change) は既に導入済み。このスキルは「既に立った PR の後処理 / cross-ecosystem 統合 / groups 未対応 ecosystem 追加時の後方互換」を担う。

## Steps

1. **前提チェック**
   - `git status --porcelain` が空でなければ報告して停止
   - 現在ブランチがデフォルトブランチでなければ、デフォルトブランチに移動する
2. **列挙 + 分類**
   - `gh pr list --author app/dependabot --state open --json number,title,headRefName,url,body,labels > "$TMPDIR/dependabot-prs.json"`
   - `bash "$HOME/.claude/skills/dependabot-bulk/scripts/list-dependabot-prs.sh" < "$TMPDIR/dependabot-prs.json"`
   - 出力 JSON の各要素: `{number, title, headRefName, url, package, ecosystem, semver, security, breaking_hint}`
3. **表を提示**

   | # | パッケージ | X→Y | semver | ecosystem | ⚠ |
   |---|---|---|---|---|---|
   | ... | ... | ... | patch/minor/major/unknown | github-actions/npm/unknown | 🛡=security / 💥=breaking_hint |

4. **統合計画を判定 (default rule)**
   - **major** → 個別維持 (統合対象外)。breaking change の判断は人間がやる
   - **patch / minor** → 統合対象。ecosystem 横断で 1 PR にまとめる (ecosystem 別分割はしない)
   - **unknown** (semver パース不能) → 安全側で個別維持
   - **security ⚠ (🛡)** → 統合に含めるが表で ⚠ 表示し、user に「単独で先行 merge するか」を明示的に確認する
   - **breaking_hint ⚠ (💥)** → 統合対象のままだが表で ⚠ 表示 (release notes 内の "breaking" / "deprecat" 検出のみで意味的判断はしない)
   - **統合対象が 1 件以下** → 「統合の意味なし。原本 PR をそのまま merge 推奨」と報告して停止
5. **Walkthrough → user 承認待ち** (pr skill step 5 と同型)
   - 統合対象・個別維持・security 単独先行の 3 リストを提示
   - user が `all` 等の明示指示で起動していない限り、次 turn の user 応答を待つ
6. **統合ブランチ作成**: `git checkout -b deps/bulk-$(date +%Y-%m-%d)`
7. **依存ごとに 1 commit を積む** (ecosystem で取り込み方が違う)
   - **github-actions**: `git fetch origin <headRefName> && git cherry-pick FETCH_HEAD`
     - 同一ファイル (test.yml) 複数 bump でも pin コメント行単位で解消可能
   - **npm**: cherry-pick **しない** (lockfile が世代衝突するため)
     - `pnpm up <pkg>@<Y>` (対象 ecosystem の複数依存があればまとめて指定)
     - `git add package.json pnpm-lock.yaml && git commit -m "<原本 title>" -m "統合元: #<N>"`
     - 依存ごとに 1 commit を保つ (CI 赤時の bisect のため)
   - commit message body に `統合元: #<N>` を書けば統合 PR body から原本 PR に辿れる。release notes 全文転記は不要
8. **ローカル検証**: `make test && make lint`
9. **push は 1 回だけ**: `git push -u origin deps/bulk-<YYYY-MM-DD>`
10. **CI 完走待ち**: `gh run watch <run-id> --exit-status`
    - verify-ci-before-pr hook が最終ゲート。`--draft` bypass は使わない
11. **統合 PR 作成**: `gh pr create --title <title> --body-file "$TMPDIR/pr-body.md"`
    - PR body テンプレは下記 「PR body」 節を参照
    - block-dangerous-commands hook 対策のため `--body-file` (heredoc / インライン文字列は使わない)
12. **原本 PR の close (統合 PR 作成直後)** ← rebase 起因 CI を止めるため作成直後に閉じる
    - `gh pr comment <N> --body "統合済み: <統合PRリンク>"`
    - `gh pr close <N>`
    - 統合対象の全 PR に対してループ。個別維持した major / security 単独先行の PR は close しない
13. **Report format で結果報告** (下記参照)

## 特記事項

### `/simplify` は免除

このスキルで作る統合 PR は Dependabot 由来で authored code がない (lockfile と yml の pin 番号のみ)。人が書いたコードのレビュー対象がないため、`/simplify` は免除する。MEMORY `feedback_simplify_every_pr` は「変更が小さい」でのスキップを禁じているが、本ケースは「著者が Dependabot / 内容が数字更新のみ」という質的例外として扱う。`/code-review` も同様の判断で省略してよい。ただし tier=high の ci-config ルールに hit する変更 (test.yml 大量 bump 等) が含まれる場合は codex-review の実施を検討する。

### verify-ci-before-pr hook の扱い

skill の flow (push → `gh run watch` で完走待ち → PR 作成) は既存 hook の要件 (HEAD の CI green) と一致するため回避せず活用する。`--draft` bypass は使わない。

### 失敗時 (CI 赤)

- 依存ごと 1 commit にしてあるので `git revert <疑い commit>` → 再 push (CI 2 回目) で二分探索できる
- npm 側が疑わしければ push 前に `make test` で切り分け可能
- 原因 commit は revert したまま統合 PR を green で通し、原因依存は原本 Dependabot PR を reopen (`@dependabot recreate` を閉じた PR の comment で復活可能) して個別追跡に戻す

### やらないこと

- 外部 fetch (CHANGELOG crawl / OSV / GHSA API 照会) はしない。Dependabot が body に埋めた情報のみを Read する
- 統合 PR の merge 実行 (user 操作)
- `dependabot.yml` 自体の書き換え
- auto-merge 設定
- `dependabot rebase` の利用 (rebase = 原本 branch への push = CI 消費、目的に逆行)

## PR body

```
## 統合対象

| # | パッケージ | X→Y | semver | ecosystem | ⚠ |
|---|---|---|---|---|---|
| #<N> | <pkg> | <X>→<Y> | minor | github-actions |  |
...

## 個別維持 (統合外)

- #<N> <pkg> <X>→<Y> (major)
- ...

## 検証エビデンス

- ローカル: `make test` PASS / `make lint` clean
- CI: <run-id> success (verify-ci-before-pr hook 経由で確認済み)

## 原本 PR

- #<N> → close 済 (comment でリンク付与)
- ...
```

## Report format

### Consolidated Dependabot PRs

**統合 PR**: <URL>

**統合済み** (N 件):
- #<N> <pkg> <X>→<Y> (semver / ecosystem)
- ...

**個別維持** (K 件):
- #<N> <pkg> <X>→<Y> (major / unknown / security 単独先行)

**検証**: `make test` PASS / `make lint` clean / CI <run-id> success
