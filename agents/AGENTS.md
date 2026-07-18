# AI Agent Guidelines

## 言語

- ユーザーへの返答・報告はすべて**日本語**で行う
- コミットメッセージも日本語で書く(type プレフィックスは英語)

## Shell 環境

- ユーザーの interactive shell は **fish**。手で叩かせるコマンドは fish 構文で提示する
  - 環境変数: `set -gx FOO bar` (not `export FOO=bar`)
  - 一時的な env: `env FOO=bar cmd` (not `FOO=bar cmd`)
  - エイリアス相当: `abbr` または `function` (not `alias FOO=...`)
  - 設定再読み込み: `source ~/.config/fish/config.fish` (not `source ~/.zshrc`)
- Claude Code / codex の Bash tool は zsh 経由なので agent 自身のコマンドは影響を受けない

## ブランチと開発フロー

- **main への直接コミット禁止**。変更は 作業ブランチ → PR → レビュー → merge の順で行う
- ブランチ名は英語小文字とハイフン: `feature/<機能名>` `fix/<バグ名>` `refactor/<対象>` `docs/<対象>`

## コミットメッセージ

```
<type>: <subject(日本語)>

<body(箇条書き)>
```

- type: `feat`(新機能) `fix`(バグ修正) `refactor` `style` `docs` `chore`
- 例: `feat: 共通部分分析ページを追加`

## Git 禁止事項

以下のうち force push と reset --hard は hook でもブロックされる。いずれの禁止事項も、回避せず新しいコミットの追加で対応する。

- `git push --force` / `--force-with-lease`(ユーザーの明示的な許可なく実行しない)
- push 済みコミットへの `git commit --amend`
- `git reset --hard`
- push 済みブランチへの `git rebase`(push 前のローカル整理のみ可)

## コード品質

- lint エラーはコードを修正して解消する。無効化コメント(`eslint-disable` 等)の追加は禁止
- 新しい関数・抽象・依存を追加する前に、リポジトリ内の既存実装を検索して再利用を検討する。タスクに不要なリファクタや機能追加はしない

## 報告

- テスト結果・完了状態を報告する前に、各主張がこのセッションのツール実行結果と対応しているか照合する。実行していないことを実行したと書かない
- レビュー指摘への対応は入口を問わず (Copilot / 人間 / レビューツール)、指摘ごとに「修正済み (コミットハッシュ) / 対応しない + 理由」を表形式で報告し、すべての指摘に回答する
- 同じ内容の指摘・訂正をユーザーから 2 回受けたら、CLAUDE.md または該当 skill への追記を提案する

## モデル分担ルール

- 統括・意思決定・PR 作成はメイン(Opus 世代)。詳細 plan の実装や並列 fan-out(観点別レビュー finder など)は中モデル(Sonnet 世代)にサブエージェント委譲する
- **生成者とレビュアーは同一モデル系統にしない**。独立第二意見は別系統(Fable 等)のサブエージェントに任せる
- サブエージェント委譲は「自己完結タスク → 結果を返す型」に限る(逐次質問はメインで拾う)

詳細な役割対応・切り替え運用・根拠は dotfiles の docs/ai-operations.md §1 を参照。
