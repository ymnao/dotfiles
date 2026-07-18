---
name: dev
description: 1 開発サイクル (タスク着手 → 実装 → レビューループ → PR 作成) を 1 コマンドで実行する umbrella skill。issue 番号・自由文・引数なし (HANDOFF 継続) のいずれでも起動できる
---

タスクの受付から PR 作成までを 1 コマンドで実行する。人間のゲートは
「非自明タスクの plan 承認」と「PR の merge」の 2 点に絞り、その間の
simplify / code-review / codex-review / pr の個別指示を不要にする。

サイクル全体: `/dev` → (plan 承認) → 実装 → レビューループ → PR 報告で停止
→ user が GitHub 上でレビュー & merge → `/next` → `/clear` → 次の `/dev`。

## Steps

### 1. タスク受付 (引数で分岐)

- **issue 番号** (`/dev 42` / `/dev #42`): `/issue` skill の手順に従う
  (issue 取得 → state 確認 → ブランチ作成 → 実装 plan 提案)。
  `/issue` が plan を提案した時点で step 2 の判定に合流する
- **引数なし**: プロジェクトルートの `HANDOFF.md` を読み、「未完了・次に
  やること」の最優先タスクを対象にする。HANDOFF.md が無い・残タスクが
  曖昧な場合はタスク内容を user に確認して停止する
- **自由文** (`/dev <タスク記述>`): 記述内容をそのままタスクとする

いずれの場合も、main 以外にいる・uncommitted changes がある場合は
状況を報告して user の指示を待つ (勝手に stash / checkout しない)。
main にいる場合は `feature/` `fix/` `refactor/` `docs/` + 英語小文字ハイフン
のブランチを作成する。

### 2. Plan チェックポイント (非自明タスクのみ停止)

タスクが以下のいずれかに該当する場合、**実装前に** plan (変更ファイル・
実装手順・考慮点) を提示して user の承認を待つ:

- 新機能・新ツールの追加 (既存の修正ではない)
- 設計判断の分岐がある (複数の実装方式から選ぶ必要がある)
- hooks / settings / security 境界に触れる
- 変更見込みが 3 ファイル超、または既存挙動を変える

該当しない場合 (バグ修正・テスト追加・doc 修正・機械的リファクタ等の
自明タスク) は plan を 1-3 行で示すだけで停止せず実装に進む。
判断に迷ったら停止する側に倒す。

### 3. 実装

plan に沿って実装し、コミットする (コミット規約は CLAUDE.md 準拠)。
実装中に plan と食い違う事実が見つかったら、乖離が大きい場合は
user に報告して指示を待つ。

### 4. レビューループ (最大 2 周)

以下を順に実行する。**修正が入ったら再度 1 周目から回す (上限 2 周)**。
2 周目でも新規指摘が出た場合は残りを fix せず記録し、step 5 の /pr の
fix-or-issue ポリシーに委ねる (発散防止)。

1. `/simplify` — 指摘を apply (skip 判断は理由を記録)
2. `/code-review medium --fix` — CONFIRMED / PLAUSIBLE を fix。fix しない
   判断をした finding は理由を記録 (step 5 で issue 起票対象になる)
3. プロジェクトのテストスイート (`make test` 等) — fail したら直す
4. コミット (レビュー修正分)

codex-review は step 5 の /pr が risk tier に応じて実行するため
ここでは呼ばない (重複実行の回避)。

### 5. PR 作成

レビューループの最終 commit 直後にまず `git push -u origin <branch>` で
push し、CI 実行と後続の evidence 組み立て・issue 起票を並走させる
(CI green 確認ゲート自体は維持)。
その上で `/pr` skill を実行する (risk 分類 → tier 別 codex-review →
fix-or-issue → evidence 付き PR 作成まで /pr の手順に従う)。

### 6. 停止

PR URL と evidence 要約を報告して**停止する**。merge はしない
(user が GitHub 上でレビューして merge するのが監視ゲート)。
merge 後の後続は `/next` skill が担う。

## 注意

- このスキルは既存 skill (issue / simplify / code-review / pr) の
  orchestrator であり、各 skill の手順を上書きしない。矛盾がある場合は
  個別 skill の記述が優先
- レビューループの上限 2 周は発散防止の意図的な制限。上限到達で残った
  finding は /pr の fix-or-issue ポリシー (fix か issue 起票) で必ず
  行き先が付くため、黙って消えることはない
- PR 作成は明示指示待ちの原則 (memory) の例外: `/dev` の起動自体が
  PR 作成までの明示指示とみなす
