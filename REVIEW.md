# REVIEW.md

この repo のレビューで前提にすること。codex-review (`claude/skills/codex-review/`) は
このファイルを base ブランチから読み、全観点のプロンプトに足す。

## 実行環境

- シェルスクリプトは macOS 標準の `/bin/bash` (3.2) でも動かす。bash 4+ の機能
  (`${var,,}` `${var^^}`、版確認の無い連想配列、`mapfile` / `readarray`、配列と `<<<`) は使わない
- macOS (BSD) と Linux (GNU) の coreutils の両方で動かす。`sed -i` は使わない (引数仕様が非互換)。
  `grep -P`、`readlink -f`、`date -d` / `stat -c` 等の GNU 拡張も使わない
- hook が自分の位置から repo 内のファイルを辿るときは、`dirname` を `pwd -P` で実体へ解決してから
  上がっているか。`~/.claude/hooks` と `~/.codex/hooks` は dir symlink なので、`<hooks>/../..` を一度に
  `cd` すると `..` が文字列のまま畳まれて `$HOME` に着く。テストもその起動形 (dir symlink 越し) で走らせる。
  実例 (#452): 新しい hook が repo の textlint を見つけられず、常に何もせず通していた

## テスト

- `~/.claude/` や `~/.codex/` から状態を読む hook のテストは、そこを stub しているか
- bash 3.2 で動くことを、bash 4+ の機能でしか通らないテストで確かめたことにしていないか
- `~/.config/git/ignore` などホストの状態を書き換えるテストは、元に戻しているか

## セキュリティ

- `.local` `.private` `.env*` 系のファイルは gitignore のまま保ち、`.gitignore` を迂回する
  パスを足さない
- `agents/hooks/guard-pkg-install.sh` は guardrail で、セキュリティ境界ではない (範囲はヘッダー)。
  回避形を指摘するときは、agent が実際に書く形かどうかを添える。わざと組み立てた形は指摘しない (#482)
