# issue-suggest

入力欄のカーソル直前の語が `#` で始まると、その repo の open issue を入力欄の上の帯に
最大 5 件並べる Claude Code の mod。押すとその語が `#N ` に置き換わる。
`/dev #42` を打つたびに issue 番号を GitHub で調べに行く手間をなくすためのもの (#427)。

- `#` の後が数字なら番号の前方一致、それ以外ならタイトルの部分一致 (大文字小文字は無視) で絞る
- 置き換えはカーソルの後ろに続く数字まで含める。`#42の件` のように空白なしで続く文字は消さない
- 一覧はカーソルが `#` の語に入ったとき (打ち始め・矢印での移動) に `gh issue list --state open --limit 100` で取り直す。
  キー入力ごとには叩かない。`gh` が無い・GitHub repo でないときは何も出さない。
  一度取れたあとに取り直しが失敗したときは、前の一覧のまま出す

## なぜ入力欄の補完 (`prompt.autocomplete`) ではないか

skill の `/` 候補と同じ場所に出せる `prompt.autocomplete` は、Claude Desktop の Code タブの
入力欄では発火しない (2026-10-12、CLI 2.1.295。確認用 mod で `#` を打っても hook が呼ばれず、
同じ mod の `session.start` の記録は残った)。普段の利用は Desktop なので、Desktop でも描かれる
入力欄の上の帯 (`AbovePrompt`) と、Desktop でもキー入力ごとに発火する `prompt.edit` で組んだ。

## 制約

- 候補はクリックで選ぶ。キーボードで帯にフォーカスを移して選べるかは確かめていない
- 置き換えるとカーソルは末尾に移る (`$.prompt.fill` に位置を指定する手段が無い)
- Desktop では `#4` の直後に打った Space が `prompt.edit` として届かず、次の文字を打つまで帯が残る。
  日本語入力の確定はカーソル位置 0 で届くことがあり、そのあいだ帯が消える (確定の Enter で戻る)。
  どちらも 2026-10-12、CLI 2.1.295 で `prompt.edit` を記録して確認した
- function hooks は early access の API で、Claude Code の更新で読まれなくなることがある。
  その場合も入力欄の編集には手を出さない作りなので、帯が出なくなるだけ

## 有効化

`claude/settings.json` の `env` にある `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1` が要る
(idle-compactor と共有)。`enabledPlugins` と `extraKnownMarketplaces` の entry は repo に入れてあり、
marketplace はセッション起動時に登録される。`marketplace add` を打たない理由と、
下のコマンドが崩す settings.json の整形の後始末は
[idle-compactor の README](../idle-compactor/README.md) の「有効化」節と同じ。
初回は新しいセッションを 1 度起動してから次を実行する。

```fish
claude plugin install issue-suggest@issue-suggest --scope user
```

## テスト

```fish
claude plugin test claude/plugins/issue-suggest/plugin
```

`make test` と CI には載せていない (CI に claude CLI が無い。idle-compactor と同じ扱い)。
