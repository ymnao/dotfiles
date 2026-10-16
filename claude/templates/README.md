# claude/templates/

新規プロジェクトにコピーして使う Claude Code 用テンプレート。各ディレクトリに
`CLAUDE.md`(コマンド表+最小の注意)と `.claude/settings.json`(権限)が入っている。

- 使い方: プロジェクトルートに両ファイルをコピーし、コマンド表を実プロジェクトに合わせて編集する
- PM の安全規則(依存追加ブロック等)は guard-pkg-install hook が全リポジトリで強制するため、CLAUDE.md には書かない
- GitHub Actions の action pin の規約は `claude/rules/github-actions.md`(`~/.claude/rules/` 経由で全リポジトリに効く)に置き、CLAUDE.md には書かない。テンプレートの CI 節は PM 固有の行だけ
- 新しい言語のテンプレートは「必要が顕在化したら」追加する(先回りで作らない)
