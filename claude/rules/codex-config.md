---
paths:
  - "**/codex/config.toml"
  - "**/codex-merge-config.sh"
  - "**/codex-merge-config.ps1"
  - "**/link.sh"
  - "**/link.ps1"
---

# codex 設定ファイルの書き込み制約

- **`~/.codex/config.toml` への書き込みは全経路で禁止**。Bash 経路は sandbox の
  `denyWrite` + `block-dangerous-commands.sh` が、Edit / Write / apply_patch の
  file 編集 tool 経路は `guard-codex-dir.sh` が block する。`notify` /
  `mcp_servers` / `hooks` / `shell_environment_policy` が host 側の任意コマンド
  実行に繋がるため (issue #190)。**読み取りは許可されている**
- **`scripts/codex-merge-config.sh` を agent から実行しない**。sandbox の
  denyWrite で必ず失敗する (仕様。sandbox 側に例外は切らない)。設定を
  反映したいときはユーザーに手元の shell での実行を依頼する
- `make link` / `make install` は agent が実行しても中断しない (config.toml の
  マージだけが warn でスキップされる) が、**config.toml は反映されない**。
  反映が必要ならユーザーに依頼する
- repo 内の `codex/config.toml` が正本。設定変更はこちらを編集し、
  反映はユーザーの手動実行に委ねる
- 防御層の全体像と regression test の所在は
  [docs/ai-operations.md](../../docs/ai-operations.md) §10 を参照
