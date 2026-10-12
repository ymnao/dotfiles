# issue-suggest

入力欄のカーソル直前の語が `#` で始まると、その repo の open issue を入力欄の上の帯に
最大 5 件並べる Claude Code の mod。押すとその語が `#N ` に置き換わる。
`/dev #42` を打つたびに issue 番号を GitHub で調べに行く手間をなくすためのもの (#427)。

- `#` の後が数字なら番号の前方一致、それ以外ならタイトルの部分一致 (大文字小文字は無視) で絞る
- 置き換えはカーソルの後ろに続く数字まで含める (`#4|2` で押しても `2` が残らない)。
  日本語が空白なしで続く `#42の件` の「の件」は消さない
- 一覧は `gh issue list --state open --limit 100` で、セッション開始時と `#` の語を打ち始めたときに取り直す。
  キー入力ごとには叩かない。`gh` が無い・GitHub repo でない・失敗したときは何も出さない

## なぜ入力欄の補完 (`prompt.autocomplete`) ではないか

skill の `/` 候補と同じ場所に出せる `prompt.autocomplete` は、Claude Desktop の Code タブの
入力欄では発火しない (2026-10-12、CLI 2.1.295 で確認用 mod を読み込み、`#` を打っても hook が
呼ばれず、同じ mod の `session.start` の記録は残った)。普段の利用は Desktop なので、
Desktop でも描かれる入力欄の上の帯 (`AbovePrompt`) とキー入力ごとの `prompt.edit` で組んだ。
同じ日に Desktop で次も確かめた: `prompt.edit` の `text` / `cursor` / `start` / `end` / `inputText` と
`next(e)` の戻りが編集の前後を正しく返す、`$.prompt.fill` で入力欄の中身を置き換えられる、
mod から `gh` が動く (cwd は repo のルート)。

## 制約

- 候補はクリックで選ぶ。Tab や矢印キーでは選べない
- 置き換えるとカーソルは末尾に移る (`$.prompt.fill` に位置を指定する手段が無い)
- function hooks は early access の API で、Claude Code の更新で読まれなくなることがある。
  その場合も入力欄の編集には手を出さない作りなので、帯が出なくなるだけ

## 有効化

`claude/settings.json` の `env` にある `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1` が要る
(idle-compactor と共有)。`enabledPlugins` と `extraKnownMarketplaces` の entry は repo に入れてある。

```fish
claude plugin marketplace add ~/development/important/dotfiles/claude/plugins/issue-suggest --scope user
claude plugin install issue-suggest@issue-suggest --scope user
```

どちらも `~/.claude/settings.json` (= repo の `claude/settings.json`) を書き直してキー順と整形が
崩れるので、実行後に `git diff claude/settings.json` を見て整形だけの差分なら
`git restore claude/settings.json` で戻す (idle-compactor の README と同じ)。

## テスト

```fish
claude plugin test claude/plugins/issue-suggest/plugin
```

`make test` と CI には載せていない (CI に claude CLI が無い。idle-compactor と同じ扱い)。
