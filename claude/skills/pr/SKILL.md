---
name: pr
description: 現在のブランチからPRを作成する
---

現在のブランチの変更内容からPRを作成してください。

## 手順

1. `bash "$HOME/.claude/skills/pr/scripts/gather-branch-info.sh"` を実行してブランチ情報を取得
2. 事前チェック:
   - `existing_pr` が null でない場合 → 「このブランチには既にPRがあります: <URL>」と報告して終了
   - `commit_count` が 0 の場合 → 「ベースブランチからのコミットがありません」と報告して終了
3. コミット履歴とdiff statを分析してPRタイトルと本文を生成:
   - **タイトル**: 70文字以内、変更の要約（日本語可）
   - **本文**: 以下のフォーマットに従う
4. `has_remote` が false の場合、`git push -u origin <branch_name>` でリモートにpush
5. `gh pr create` でPRを作成:
   - `linked_issue` がある場合は本文に `Closes #<番号>` を含める

## PRテンプレート

```
## Summary
<変更内容を箇条書きで1-3項目>

## Test plan
<テスト方法を箇条書き>

Closes #<イシュー番号>（該当する場合のみ）
```

## 報告フォーマット

PRを作成しました: <PR URL>

| 項目 | 内容 |
|------|------|
| ブランチ | `<branch_name>` → `<base_branch>` |
| コミット数 | <commit_count> |
| 変更ファイル | <files_changed> files (+<insertions> -<deletions>) |
