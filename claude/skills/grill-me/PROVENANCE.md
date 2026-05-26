# grill-me skill — Provenance

このディレクトリの `SKILL.md` は upstream から手動コピーで導入しています。
将来 update する際は、必ず本ファイルの記録と差分を比較してください。

## Upstream

- **Author**: Matt Pocock
- **Repository**: https://github.com/mattpocock/skills
- **Path**: `skills/productivity/grill-me/SKILL.md`
- **License**: MIT — 本ファイルと同階層の [`LICENSE`](./LICENSE) に upstream の
  著作権表示と許諾表示を同梱しています。
- **Source URL (blob, content-addressed)**: https://github.com/mattpocock/skills/blob/b8be62ffacb0118fa3eaa29a0923c87c8c11985c/skills/productivity/grill-me/SKILL.md

## Pinned identifiers

| 項目 | 値 |
|---|---|
| Repo commit SHA | `b8be62ffacb0118fa3eaa29a0923c87c8c11985c` |
| Repo commit date | 2026-05-20T08:46:53Z |
| SKILL.md blob SHA-1 | `bd04394c675ee54173a093c50eb74da01a2940fa` (635 bytes) |
| LICENSE blob SHA-1 | `f1dd2c09108dde1a5f56097cee8461b3ea834499` (1068 bytes) |
| 取得日 | 2026-05-26 |

## 検証手順 (再現可能)

`base64 --decode` は GNU / macOS(BSD) どちらでも動作するため、OS差分を
吸収するために `-d` ではなく `--decode` を使っています。

```bash
# SKILL.md
gh api repos/mattpocock/skills/git/blobs/bd04394c675ee54173a093c50eb74da01a2940fa \
  --jq '.content' | base64 --decode > /tmp/grill-me-skill.md
git hash-object /tmp/grill-me-skill.md
# => bd04394c675ee54173a093c50eb74da01a2940fa が出れば改ざん検出されず

# LICENSE
gh api repos/mattpocock/skills/git/blobs/f1dd2c09108dde1a5f56097cee8461b3ea834499 \
  --jq '.content' | base64 --decode > /tmp/grill-me-LICENSE
git hash-object /tmp/grill-me-LICENSE
# => f1dd2c09108dde1a5f56097cee8461b3ea834499 が出れば改ざん検出されず
```

Git blob は SHA-1 で content-addressed なので、SHA が一致すれば upstream
公開時点と内容が同一であることの **強い根拠** となります。ただし SHA-1 は
2017年の SHAttered 攻撃で衝突が実証されており、暗号学的に絶対的な保証では
ありません (git も SHA-256 への移行を検討中)。

より強い保証が必要な場合は以下の補助検証を組み合わせることを推奨します:

- `gh api repos/mattpocock/skills/commits/<sha>` で commit 署名 (verification)
  の有無を確認する
- 上流の署名付きタグ / リリースが提供されている場合はそれを参照する
- ローカルで `git verify-commit <sha>` / `git verify-tag <tag>` を実行する

## なぜ npm 経由でインストールしないのか

公式の案内 `npx skills@latest add mattpocock/skills` は採用していません。
2025年末〜2026年5月にかけて以下の重大な npm/GitHub サプライチェーン攻撃が
連続して発生しており、`npm install` の postinstall および npm 依存ツリー
全体が攻撃面になっているためです。

- 2025-09 / 2025-12 Shai-Hulud / Shai-Hulud 2.0 (自己増殖型ワーム)
- 2026-03-31 Axios 1.14.1 / 0.30.4 改ざん (Microsoft 帰属: Sapphire Sleet)
- 2026-04-29 Mini Shai-Hulud (SAP npm 群)
- 2026-05-11 TanStack 42パッケージ・84アーティファクト改ざん
  (有効な SLSA provenance をバイパス)
- 2026-05-14 node-ipc 3バージョン改ざん
- 2026-05-20 @antv maintainer 乗っ取り (echarts-for-react 等が下流影響)

本 skill は SKILL.md 1ファイル・635バイトの平文テキストであり、スクリプトも
外部 fetch も含まないため、blob を直接取得して目視確認する方式が最小サーフェス
で完結します。

## Update 手順

1. upstream の最新コミット SHA を確認: `gh api repos/mattpocock/skills/commits/main`
2. SKILL.md / LICENSE の新しい blob SHA をそれぞれ取得し、ローカルで
   `git hash-object` で再検証 (上記「検証手順」と同じ要領)
3. 差分を `diff` で確認し、内容に問題がないことをレビュー
4. 本ファイルの pinned identifiers (SKILL.md / LICENSE 両方) と取得日を更新
5. ブランチを切ってコミット
