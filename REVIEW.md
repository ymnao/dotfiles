# REVIEW.md

この repo のレビューで前提にすること。codex-review (`claude/skills/codex-review/`) は
このファイルを base ブランチから読み、全観点のプロンプトに足す。

## 実行環境

- シェルスクリプトは macOS 標準の `/bin/bash` (3.2) でも動かす。bash 4+ の機能
  (`${var,,}` `${var^^}`、版確認の無い連想配列、`mapfile` / `readarray`、配列と `<<<`) は使わない
- macOS (BSD) と Linux (GNU) の coreutils の両方で動かす (`sed -i ''`、`grep -P`、
  `readlink -f`、`date -d` の差)

## テスト

- `~/.claude/` や `~/.codex/` から状態を読む hook のテストは、そこを stub しているか
- bash 3.2 で動くことを、bash 4+ の機能でしか通らないテストで確かめたことにしていないか
- `~/.config/git/ignore` などホストの状態を書き換えるテストは、元に戻しているか

## セキュリティ

- `.local` `.private` `.env*` 系のファイルは gitignore のまま保ち、`.gitignore` を迂回する
  パスを足さない
