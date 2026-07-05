# skill evals

ワークフロー系 skill(pr / issue / resolve / codex-review)の振る舞いテスト。
配置先: `claude/skills/<skill>/evals/`(このディレクトリの内容を skill ごとに配る)。

## 実行方法(共通)

- 実行モデルの既定は **Sonnet 5**:
  Setup 済みディレクトリで `claude --model claude-sonnet-5 -p "<Prompt の内容>"`
  を実行する。skill-creator(公式 skill)の eval 実行機能が使える環境では
  そちらを優先してよい
- 判定: Pass criteria の各項目を、セッション出力・生成物・`gh` の状態で確認する
- 各 eval は **3 回実行し 3/3 PASS で合格**(非決定性によるブレの検出)
- モデル移行時(例: Fable → Sonnet)は全 eval を一括実行して壊れた skill を特定する

## サンドボックスリポジトリ(pr / issue / resolve 用)

実 GitHub 操作を伴うため、専用のダミーリポジトリで実行する。
**実プロジェクトでは絶対に実行しない。**

初回セットアップ:

```bash
gh repo create <your-account>/skill-eval-sandbox --private --clone
cd skill-eval-sandbox
bash <dotfiles>/claude/skills/codex-review/evals/seed-sandbox.sh
```

seed-sandbox.sh は初期コミット・ラベル・eval 用 issue を作成する(冪等)。
eval が作成した PR / ブランチは各 eval の Cleanup 手順で削除する。

## codex-review 用の注意

- codex CLI が必要。未インストール環境では 01/02 を SKIP と記録する
  (03 は codex 不在の挙動自体のテストなので実行できる)
- 02 の仕込み diff は `fixtures/vuln.patch` を使う。トークン文字列は明白な
  ダミー(`dummy-eval-fixture-not-real`)で、secretlint に実シークレットと
  誤検知されないことを確認済みの文字列にしてある
- 04 は PATH 上の偽 `codex` 実行ファイルで sandbox 制約 (exit 3 SKIP) を
  再現するので、03 と同様に実 codex CLI の有無に依存せず実行できる
