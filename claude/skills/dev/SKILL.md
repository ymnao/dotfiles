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

#### 2a. Pre-plan investigation (非自明タスクは必ずメインで実施)

Fable 委譲の前に、**メインが以下を調査して事実を確定させる**。Fable は
fresh context なので、渡す事実が不足すると hallucination で埋まる。委譲の
利益 (self-preference bias 回避・推論深度) は事前調査が土台。

1. **タスク面の把握**: issue 本文 / HANDOFF 記述 / 自由文の要件を書き出す
   (受け入れ条件・スコープ外を明示)
2. **影響範囲の特定**: 変更対象ファイル候補を Grep で列挙 (規模の当たり
   をつける)
3. **既存実装の確認**: 対象ファイルの該当箇所を Read。似た機能が既に
   ないか adjacent ディレクトリ (共有 utility / helper) も Grep で確認
   (再実装の予防)
4. **制約の抽出**: repo CLAUDE.md / 関連 skill / 既存 test の慣行を確認
   (repo 特有ルールに違反する plan を出さないため)
5. **不確実性の記録**: 調査中に判明した不明点 / 選択肢を列挙 (Fable に
   「この分岐で判断してほしい」と明示できるよう)

上記の成果物 (調査済み事実 + 制約 + 不確実性リスト) を Fable への prompt
に **同梱**する。Fable は repo を再探索せず、渡された事実だけで plan を
組み立てる (再探索コスト回避 + 事実整合)。

自明タスクではこの 2a はスキップ可 (1-3 行 plan と一体でメインが処理)。

#### 2b. Plan 立案の Fable 委譲

**Plan 本文の立案は Fable サブエージェントに委譲する** (メイン Opus が
自前で書かない)。self-preference bias を避けつつ推論深度を上げるため。
呼び出し方:

```
Agent(
  subagent_type: "general-purpose",
  model: "fable",
  description: "Plan for <task>",
  prompt: "<step 2a の成果物一式 (タスク要件 / 影響範囲 / 既存実装の
    該当箇所 / repo 制約 / 不確実性リスト) を渡し、変更ファイル・
    実装手順・考慮点だけを返させる。repo の再探索は不要、実装や質問は
    しないと明記する>"
)
```

メインは返ってきた plan を repo 慣行と照合し、そのまま (または軽く補正
して) user に提示する。自明タスクの 1-3 行 plan は委譲コストが上回るため
メインのまま。

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
