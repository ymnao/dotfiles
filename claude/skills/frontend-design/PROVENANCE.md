# frontend-design skill — Provenance

このディレクトリの `SKILL.md` は upstream から手動コピーで導入しています。
将来 update する際は、必ず本ファイルの記録と差分を比較してください。

## Upstream

- **Author**: Prithvi Rajasekaran, Alexander Bricken (Anthropic)
- **Repository**: https://github.com/anthropics/claude-code
- **Path**: `plugins/frontend-design/skills/frontend-design/SKILL.md`
- **License**: Anthropic 商用利用規約 — https://www.anthropic.com/legal/commercial-terms
- **Source URL (blob, content-addressed)**: https://github.com/anthropics/claude-code/blob/72281753c2af394d35d6950af5980832cbebd322/plugins/frontend-design/skills/frontend-design/SKILL.md

## Pinned identifiers

| 項目 | 値 |
|---|---|
| Repo commit SHA | `72281753c2af394d35d6950af5980832cbebd322` |
| Repo commit date | 2026-06-06T23:41:47Z |
| SKILL.md blob SHA-1 | `600b6db41fac7e2081c7528ec6982960892c819d` (4,274 bytes) |
| 取得日 | 2026-06-09 |

## 検証手順 (再現可能)

```bash
# SKILL.md
gh api repos/anthropics/claude-code/git/blobs/600b6db41fac7e2081c7528ec6982960892c819d \
  --jq '.content' | base64 --decode > /tmp/frontend-design-skill.md
git hash-object /tmp/frontend-design-skill.md
# => 600b6db41fac7e2081c7528ec6982960892c819d が出れば改ざん検出されず
```

Git blob は SHA-1 で content-addressed なので、SHA が一致すれば upstream
公開時点と内容が同一であることの **強い根拠** となります。

## なぜ npm 経由でインストールしないのか

公式プラグインではあるものの、`git clone` や `npm install` は以下の理由で
採用していません:

- `git clone --recursive` での RCE (CVE-2025-48384, CISA KEV 登録済み)
- `npm install` の postinstall スクリプト即時実行による攻撃面
- 2025〜2026年に Shai-Hulud, Megalodon, Miasma 等のサプライチェーン攻撃が連発

本 skill は SKILL.md 1ファイル・4,274バイトの平文テキストであり、スクリプトも
外部 fetch も含まないため、blob を直接取得して SHA 検証する方式が最小攻撃面で
完結します。

## Update 手順

1. upstream の最新コミット SHA を確認: `gh api repos/anthropics/claude-code/commits/main`
2. SKILL.md の新しい blob SHA を取得し、ローカルで `git hash-object` で再検証
3. 差分を `diff` で確認し、内容に問題がないことをレビュー
4. 本ファイルの pinned identifiers と取得日を更新
5. ブランチを切ってコミット
