# skill evals

skill の振る舞いテスト。配置先は `claude/skills/<skill>/evals/`。

eval を書く条件は **AGENTS.md「コード品質」節が正本**(事故が起きた挙動を
pin するときだけ)。予防目的のカバレッジ網羅は書かない。現存する eval は
以下の 3 本のみ:

- `codex-review/evals/04-sandbox-skip.md` — sandbox 起因の failure を
  「レビュー対象コードの問題」と誤解していた挙動の修正 (e4fbecc) を pin
- `codex-review/evals/05-rate-limit-skip.md` — rate limit 到達を ERROR と
  誤検出していた挙動の修正 (6b218aa) を pin
- `dev/evals/08-doc-only-pr-no-walkthrough.md` — classify-risk が doc-only
  差分を誤って tier=high にしていた挙動の修正 (91253cf) を pin

## 実行方法(共通)

- 実行モデルの既定は **Sonnet 5**:
  Setup 済みディレクトリで `claude --model claude-sonnet-5 -p "<Prompt の内容>"`
  を実行する。skill-creator(公式 skill)の eval 実行機能が使える環境では
  そちらを優先してよい
- 判定: Pass criteria の各項目を、セッション出力・生成物・`gh` の状態で確認する
- 各 eval は **3 回実行し 3/3 PASS で合格**(非決定性によるブレの検出)

## サンドボックスリポジトリ

実 GitHub 操作を伴う eval は、専用のダミーリポジトリで実行する。
**実プロジェクトでは絶対に実行しない。**

初回セットアップ:

`gh` は **単独の Bash 呼び出し**で実行する（他のコマンドと混ぜると
`guard-sandbox-exclusions.sh` にブロックされる。issue #267）:

```bash
gh repo create <your-account>/skill-eval-sandbox --private --clone
```

```bash
cd skill-eval-sandbox
bash <dotfiles>/claude/skills/codex-review/evals/seed-sandbox.sh
```

**`seed-sandbox.sh` は中身が `gh` 呼び出しなので、Claude Code の Bash tool から
起動すると sandbox 内で走って認証に失敗する**(script 名にはコマンド名が現れない
ので hook は通すが、上流の excludedCommands にもマッチしない)。この初回
セットアップは **user が sandbox 外のターミナルで手動実行**すること。

seed-sandbox.sh は初期コミットを作成する(冪等)。
eval が作成した PR / ブランチは各 eval の Cleanup 手順で削除する。

## codex-review 用の注意

- 04 / 05 は PATH 上の偽 `codex` 実行ファイルで sandbox 制約 (exit 3) と
  rate limit (exit 4) を再現するので、実 codex CLI の有無に依存せず実行できる
