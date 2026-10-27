# claude/templates/

新規プロジェクトにコピーして使う Claude Code 用テンプレート。各ディレクトリに
`CLAUDE.md`(コマンド表+最小の注意)と `.claude/settings.json`(権限)が入っている。

- 使い方: プロジェクトルートに両ファイルをコピーし、コマンド表を実プロジェクトに合わせて編集する
- PM の安全規則(依存追加ブロック等)は CLAUDE.md には書かない。agent がふだん書く依存追加は guard-pkg-install hook が全リポジトリで止め、公開直後の版を入れない等の備えは `pnpm/config.yaml` / `uv/uv.toml` / `npm/npmrc` が global の設定として持つ(hook は guardrail で、組み立てた形までは止めない)
- GitHub Actions の action pin の規約は `claude/rules/github-actions.md` が全リポジトリで `.github/` の workflow・action・dependabot 設定を触るときに読み込まれるため、CLAUDE.md には書かない
- 新しい言語のテンプレートは「必要が顕在化したら」追加する(先回りで作らない)
