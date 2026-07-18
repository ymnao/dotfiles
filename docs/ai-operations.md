# AI 運用ガイド

人間(自分)向けの運用ドキュメント。モデルが毎セッション読む AGENTS.md には
入れない(コンテキスト節約のため。確実に実行させたいルールは hook に、
毎セッション必要な最小ルールだけ AGENTS.md にある)。

## 1. モデル運用(役割分担)

AGENTS.md「モデル分担ルール」節の最小規範を、こちらで役割・モデル対応・
根拠込みに詳細化する。

| 役割 | モデル | effort | 用途 |
|---|---|---|---|
| メイン(統括・意思決定) | Opus 4.7(**4.8 は使わない**) | high(難所は xhigh) | 全体制御・decisions・並列調整・軽 verify・PR 作成 |
| **plan 立案**(非自明タスク) | **Fable** | - | `/dev` step 2 の変更ファイル・実装手順・考慮点の立案。self-preference bias 回避 + 推論深度確保のためメイン Opus からサブエージェント委譲 |
| 実装ループ(詳細 plan あり) | Sonnet 5 | high(難所は xhigh) | ファイル/関数/追加行の意図まで指定された実装、機械的 refactor、テスト追加 |
| 並列 fan-out(中軽度並列) | Sonnet 5 | high | /simplify・/code-review の観点別 finder、多点調査 |
| 独立第二意見(別モデル系統) | Fable など | - | fresh context のレビュー、難しい設計判断、cascade でメインが疑わしいと判定したときのエスカレーション先 |
| 探索・情報収集 | Haiku 4.5 | - | 軽い調査・ファイル探索 |

- 切り替え: `/model`、Agent ツールの `model` パラメータ
  (例: `Agent(subagent_type: "general-purpose", model: "sonnet", prompt: ...)`
  独立第二意見は `model: "fable"`)
- 原則: **浅い推論を見たらプロンプトを工夫する前に effort を上げる**
  (公式推奨。モデル変更より effort が先のレバー)
- レビュー系タスクで下位モデルを使うときは「重要度でフィルタせず全部
  報告 → 後段でフィルタ」の 2 段にする(literal 特性への公式対策)

### 根拠(業界 BP)

- **生成者とレビュアーは同一モデル系統にしない**: self-preference bias
  で自己生成物を過大評価する(arXiv:2410.21819)。Anthropic ネイティブの
  reviewer には Fable のような別系統を、あるいは cross-vendor(codex-review
  等)を差す
- **並列 fan-out は中モデル + orchestrator パターンが上位モデル単体より
  高性能かつ安い**: Anthropic の multi-agent research system の実測で
  Opus lead + Sonnet subagent が単体 Opus を 90.2% 上回った
- **cascade 型エスカレーション**(中モデル実装 → メイン軽 verify → 疑わし
  ければ第二意見)が静的割り当てよりコスト最適(FrugalGPT 系サーベイ)
- **委譲は「自己完結タスク → 結果を返す型」に限る**: 逐次質問往復は
  fresh context の利点を消すのでメインで拾う

## 2. Fable 5 → 下位モデル移行チェックリスト

移行日に実施:

- [ ] `claude/settings.json` の `effortLevel` を見直す(現行 "high"。
      Opus 4.8 / Sonnet 5 の高難度タスクは xhigh が公式推奨。まず high 維持
      + 難所で引き上げの運用から始め、質が足りなければ既定を上げる)
- [ ] skill eval を全件実行(Sonnet 5 で pr / issue / resolve /
      codex-review 各 3 本以上)し、壊れた skill を特定して修正する
- [ ] `make test`(hook 回帰テスト込み)を実行して基線を確認する
- [ ] 最初の 1 週間、レビュー指摘の見逃し・skill の手順飛ばしを意識的に
      観察し、気づきを CLAUDE.md / skill に反映する(下記 3)
- [ ] Fable 専用の記述が設定に残っていないか確認する
      (`grep -ri fable claude/ codex/ agents/`)

## 3. 失敗駆動の設定改善(Boris Cherny 方式)

- モデルの誤りを見たら、その場の再プロンプトで流さず
  **CLAUDE.md か該当 skill に修正を書き込む**(将来の全セッションに効く)
- 追記の品質基準: 検証可能な形で書く(「注意する」ではなく
  「X の場合は Y する」)。定期的に各行へ
  「この行を消したらミスするか?」を問い、No なら削除する
- 200 行を超えたら skill / hook への移譲を検討する

## 4. セッション運用の定石

- **開発サイクルの定型は 2 コマンド**: `/dev`(受付 → plan 承認(非自明のみ)
  → 実装 → simplify / code-review / テストのレビューループ → /pr)→ user が
  GitHub で merge → `/next`(merged 確認 → pull → 学び昇格チェック →
  handoff → 次候補提示)→ `/clear` → 次の `/dev`。人間ゲートは
  「非自明タスクの plan」と「merge」の 2 点。レビュー finding は
  fix-or-issue ポリシー(fix するか issue 起票するかの二択、未起票 defer は
  verify-ci-before-pr hook がブロック)で次セッションへの暗黙持ち越しを防ぐ
- 無関係なタスクの間で `/clear`(コンテキストを引きずらない)
- **2 回訂正して直らなければ `/clear`** し、学んだことを盛り込んだ
  プロンプトで新セッションを始める(訂正が蓄積した長セッションより、
  良いプロンプトの新セッションがほぼ常に勝つ)
- 探索・調査はサブエージェントに委任してメインのコンテキストを守る
- メモリ運用: 1 ファイル 1 教訓、先頭に 1 行サマリ、誤りと判明したら削除

## 5. MCP / skill / プラグイン追加の審査基準

新しいツールを入れたくなったら、この順で検討する:

1. **CLI で代替できるか**(gh, jq, 専用 CLI)→ CLI を使う
2. **skill 化できるか**(頻用ワークフロー・手順知識)→ skill を書く
3. どちらも不可(認証付きライブ接続等)のときのみ MCP
4. 導入審査: 出所の確認(公式 / 著名作者か)・中身を読む(skill は
   Markdown なので全文監査できる)・最小権限・lethal trifecta
   (秘密データ+信頼できないコンテンツ+外部送信の同時成立)を作らないか
5. 半年ごとに棚卸し: 「今のモデル性能でもまだ必要か?」を問う
   (例: sequential-thinking MCP は adaptive thinking 内蔵化で 2026-07 に削除済み (PR #65))

## 6. レビューと理解の保ち方

- PR の証拠セクション(pr skill が自動生成)を読む。diff 全精読は
  高リスク PR のみ(explain-the-diff ウォークスルー付き)
- 原則: **理解できないコードはマージしない**(差し戻すか説明させる)
- AI レビュー(codex-review / code-review)は信頼できる diff 専用。
  外部コントリビュータの PR に無条件で自動レビューを走らせない
  (prompt injection 前提の運用)
- 高リスク変更(セキュリティ境界・hooks・認証・リリース前最終確認)の
  merge 前は `/adversarial-review`(競争的 2 体レビュー)を使う

## 7. メモリ運用(auto memory)

auto memory(`~/.claude/projects/<project>/memory/`)は各セッション起動時に
MEMORY.md 先頭 200 行が自動ロードされる。

- 1 ファイル 1 教訓。description(recall の判定に使われる)を必ず書く
- 週 1 回か大きな作業の区切りで `/consolidate-memory` を実行する
  (重複統合・陳腐化した記述の削除・インデックス修復)
- **機微情報(トークン・社内情報・個人情報)を書かない**。メモリは
  gitignore もされず secretlint も通らない領域
- **メモリはマシン間で共有されない**。マシンをまたぐ引き継ぎはメモリに
  頼らず、リポジトリ内ファイル(HANDOFF.md 等)で行う(/handoff skill)
- 繰り返し必要になる知識はメモリに置いたままにせず、`~/.claude/rules/`
  (ファイル種別限定)か CLAUDE.md(常時)へ昇格させる。メモリは
  「昇格前の受け皿」と位置づける

## 8. permissions の定期見直し

- 移行後にプライベート PC で数セッション運用したら
  `/fewer-permission-prompts` を実行し、提案された allowlist を
  **1 件ずつ手動レビューして** `claude/settings.json` に反映・コミットする
  (提案の丸呑みはしない。書き込み系・ネットワーク系は原則入れない)
- 以後は「同じ許可プロンプトに 3 回答えたら allowlist 追加を検討」を目安にする

## 9. 導入を見送った機構(再評価条件つき)

2026-07-03 の検討(HANDOFF.md 候補 1〜10)で見送りを決めたもの。
先回りで入れず、条件を満たしたら再評価する。

| 機構 | 見送り理由 | 再評価条件 |
|---|---|---|
| GitHub Actions 連携(claude-code-action) | API 従量課金が必要(x20 定額の外)。ローカルレビューと重複。prompt injection 前提の運用が必要 | 他者コントリビュータのいるリポを持ったとき |
| Agent teams | 実験的で既知制限が多い(再開不可・ネスト不可等)。サブエージェントで足りる | GA になり、並列レビュー等で実需が出たとき |
| opusplan | plan mode を計画の境界として使っていない(セッション+仕様書で分離する運用)。/model で随時有効化できる | plan mode 中心の運用に変わったとき |
| Superpowers(obra/superpowers) | 公式マーケットプレイス外で全文監査が必要。既存 skill 群と思想が重複。更新追従がない | 同種の困りごとが 3 回起きたとき、または公式マーケットプレイス入りしたとき(その skill だけ監査して取り込む) |
| keybindings カスタマイズ | 現時点で困っている操作がない | 操作の不満が具体化したとき |
| Stop hook 駆動の review 強制ループ(claude-review-loop 系) | /dev 内の有界レビューループ(上限 2 周)で足りる。無限ループ対策(`stop_hook_active` guard)が必要になり、停止タイミングの監視性も下がる | /dev 運用でレビュー飛ばしが実際に起きたとき |
| Ralph loop 型の外側無人ループ(`while true; claude -p` 系) | merge ゲート・plan ゲートの人間監視を放棄することになる。2026-07-19 の検討で「パイプライン圧縮 + 人間ゲート再配置」(/dev + /next)を採用 | 完全無人で回してよい種類の反復タスク(大量 migration 等)が実際に発生したとき |
