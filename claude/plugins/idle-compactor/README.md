# idle-compactor (vendored)

セッションが放置されてプロンプトキャッシュ (1h TTL) が切れる直前に `/compact` を打つ
Claude Code プラグイン。キャッシュが温かいうちに圧縮しておくと、あとで戻ったときに
会話全体ではなく短い要約だけが再送される。

## 出所

| | |
|---|---|
| upstream | https://github.com/intenex/claude-idle-compactor |
| commit | `fdd49d222a3bcea6a1fffc85d72199dad3aacd7c` (2026-09-23) |
| 取り込み | 2026-09-24 |
| license | MIT (LICENSE 同梱) |

取り込んだのは `plugin/` と `.claude-plugin/marketplace.json` と `LICENSE` のみ。
`install.sh` / `Install.command` / `uninstall.sh` は **意図的に除外**している。

## なぜ marketplace 経由の auto-update にしなかったか

upstream の installer は `~/.claude/settings.json` に `autoUpdate: true` を書き込む。
upstream は 2026-09-23 作成・commit 3・star 0 の個人リポジトリで、追従している
第三者がいない。auto-update は「将来の push が無レビューでこのマシンで走る」という
意味なので切ってある。

もう一点、installer は settings.json を `NSString writeToFile:atomically:YES`
(一時ファイル + rename) で書き換える。`~/.claude/settings.json` は dotfiles への
symlink なので、rename が symlink 自体を置き換えて dotfiles から切り離される。

## upstream からの差分

- `plugin/.claude-plugin/plugin.json`: `min_context_tokens` の default を
  30000 → **50000**。idle compaction は「そのセッションに戻ってきた場合だけ」得で、
  戻らなければ要約生成ぶんが丸損になる。小さいセッションは見送る側に倒した。

`hooks/idle-compactor.ts` の `readConfig` の fallback と `tests/idle-compactor.test.ts` 冒頭の
コメントは 30000 のまま残している。manifest の default が options に入るので fallback は
通らず (2.1.280 で実測)、upstream との差分を 1 箇所に保つ方を取った。効いているかは
`/idle-compactor` の出力が `needs 50,000+ tokens` になっていることで確かめられる。

upstream を追従するときはこの 1 箇所だけ手で戻す。

## 有効化

`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1` が要る (function hooks は early access で
既定は off)。`claude/settings.json` の `env` に入れてある。このスイッチはこのプラグイン
専用ではなく、**install 済みの全プラグインの hooks module をプロセス内で読み込む**
(2.1.280 の本体の文言: "hooks modules are not turned on for installed plugins in this
process")。以後プラグインを足すときは `hooks/hooks.json` の `modules` の有無も審査に含める。

`claude plugin install` は `enabledPlugins` を `~/.claude/settings.json` (= repo の
`claude/settings.json`) に書くので、その entry は先に repo に入れてある。

```fish
claude plugin marketplace add ~/development/important/dotfiles/claude/plugins/idle-compactor --scope user
claude plugin install idle-compactor@claude-idle-compactor --scope user
```

セッション内で `/idle-compactor` を叩くと状態と直近の結果が出る。

## 前提の脆さ

function hooks は early access の API で、2.1.280 の本体も "early access: it may change
between releases" と書いている。
Claude Code を上げたあとプラグインが読まれなくなること (`Hooks (0)`) がありうる。
その場合は upstream に修正が来ていないか見る。
