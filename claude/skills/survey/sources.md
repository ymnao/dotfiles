# survey の巡回先

`/survey` skill の step 2 が読む固定リスト。
`docs/ai-operations.md` §5 の 5 番目 (半年ごとの棚卸し) と同じタイミングで見直す。

## 優先順位

1. **AI (Claude / OpenAI 等) の仕様変更** — 主
2. **海外エンジニアが公開している使い方** — 主
3. **shell / エディタ (fish / nvim / wezterm / starship)** — 副。時間と枠が余ったとき

## 2 軸

- **定点観測** (A / B / C / E) — 毎回同じ場所を見る。再現性が高く、`log.md` の
  重複排除が効く。**こちらが土台**
- **探索** (D) — 固定クエリ 2〜3 本に限定する。網羅性は上がるが毎回結果が変わり、
  候補が発散して backlog を増やす方向に働くため、自由探索にはしない

## AI 情報の取捨 (このリストで一番効く節)

Claude Code の CHANGELOG は週次で動き、使い方系の発信も高頻度。**全部を候補に
すると溢れる**。「摩擦低減 1 文が書けるか」だけでは AI の新機能はたいてい通って
しまうので、**追加条件**として次の線引きを使う。

**拾う**:

- 既存の設定・hook・skill を**壊す**仕様変更 (settings のキー変更、hook イベントの
  追加 / 廃止、permissions の意味変更)
- 今ある自作機構を**単純化できる**公式機能 (自前でやっていたことが標準搭載された)
- **現に困っている運用**に当たる使い方

**落とす** (原則、`log.md` に `rejected` で記録):

- 新モデル・新 API 機能そのもの (この repo の設定には効かない)
- ベンチマーク・性能比較
- 「知っておくと良い」止まりの読み物
- 導入に別サービスの契約が要るもの

この線引きを外すと、この skill は週次のニュースレターになって摩耗する。

## A. 定点観測 — dotfiles (4 枠)

### 選定基準

- **(a) 参考になる軸を持つ** — AI 設定 (CLAUDE.md / `.claude/` / codex) を公開して
  いるか、fish / nvim / wezterm / starship / macOS を実際に使っている
- **(b) 直近 6 か月以内に更新がある** — 更新が止まった dotfiles は、その人が今どう
  困っているかの情報を持たない
- **(c) 本人が日常運用している実物である** — 「書き方の見本」として作られた repo
  ではなく、実際に毎日動いているもの

(b) は `/survey` step 2 で毎回実測する (満たさなくなったときの扱いは SKILL.md step 2)。

### AI 設定枠 (2)

| 巡回先 | 軸 | 最終更新 (実測) |
|---|---|---|
| [citypaul/.dotfiles](https://github.com/citypaul/.dotfiles) | CLAUDE.md / skills / agents / slash commands (696 stars) | 2026-07-31 |
| **(空き)** | 初回サーベイで探して埋める。有力候補は [zircote/.claude](https://github.com/zircote/.claude) (agents / skills / commands、ただし 2026-02-03 更新で基準 (b) の境界) | — |

### shell / エディタ枠 (2)

| 巡回先 | 軸 | 最終更新 (実測) |
|---|---|---|
| [folke/dot](https://github.com/folke/dot) | nvim (lazy.nvim 作者), macOS | 2026-04-17 |
| [mattmc3/dotfiles](https://github.com/mattmc3/dotfiles) | fish, macOS | 2026-07-11 |

### 除外の記録

再調査の重複を避けるために残す。

| 候補 | 除外理由 |
|---|---|
| craftzdog/dotfiles-public | AI 設定を含まず、shell / エディタ枠は folke / mattmc3 で足りるため 2026-07-31 に外した (基準未達ではない) |
| mathiasbynens/dotfiles | 基準 (b) 未達 — 最終更新 2024-08 |
| jorgebucaran/cookbook.fish | 基準 (b) 未達 — 最終更新 2023-09 |
| sindresorhus/dotfiles | repo が存在しない (404) |
| jdx/dotfiles | repo が存在しない (404) |

## B. 定点観測 — AI の仕様変更

| 情報源 | 見るもの |
|---|---|
| [Claude Code CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) | hook / skill / settings / permissions の追加・変更 |
| [Anthropic Engineering blog](https://www.anthropic.com/engineering) | 運用・設計の深掘り |
| [ChatGPT & Codex changelog](https://learn.chatgpt.com/docs/changelog) | codex CLI / ChatGPT 側の変更 |
| [openai/codex releases](https://github.com/openai/codex/releases) | codex CLI 本体 |

`docs.claude.com` の release-notes は Claude Code CHANGELOG に redirect する
(同じ情報源なので二重に見ない)。

## C. 定点観測 — 使い方

**差分として持ち込める形になっているものだけ**候補にする (hook / skill / CLAUDE.md
の書き方など)。「良い記事だった」で終わるものは候補表に載せない。

| 情報源 | 見るもの |
|---|---|
| [Simon Willison — claude-code タグ](https://simonwillison.net/tags/claude-code/) | 実運用の観察と落とし穴 |
| [awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) | skill / hook / command の実例カタログ |
| [anthropics/claude-cookbooks](https://github.com/anthropics/claude-cookbooks) | 公式の実装例 |

## D. 探索 (固定クエリ 2〜3 本)

定点観測で拾えないものだけを拾う。**クエリを増やさない** — 増やすと発散する。

1. `Claude Code hooks skills 実践 <直近の年月>` — 運用記事
2. `codex CLI AGENTS.md 運用 <直近の年月>` — codex 側の運用記事
3. (任意) 今サイクルで実際に困っている具体語 1 本

## E. 定点観測 — shell / エディタ (副)

| 情報源 | 見るもの |
|---|---|
| [fish-shell releases](https://github.com/fish-shell/fish-shell/releases) | 構文・組み込み関数の変更 (設定の書き換えが要るもの) |
| [neovim releases](https://github.com/neovim/neovim/releases) | API 変更・非推奨化 |
| [wezterm releases](https://github.com/wezterm/wezterm/releases) | 設定スキーマの変更 |
| [starship releases](https://github.com/starship/starship/releases) | モジュール追加・設定キーの変更 |
| [This Week in Neovim](https://dotfyle.com/this-week-in-neovim) | プラグイン・設定の動向 |
