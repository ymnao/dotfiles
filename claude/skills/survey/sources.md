# survey の巡回先

`/survey` skill の step 2 が読む固定リスト。
`docs/ai-operations.md` §5 の 5 番目 (半年ごとの棚卸し) と同じタイミングで見直す。

## 選定基準 (dotfiles の人選)

3 つすべてを満たすものを載せる:

- **(a) スタック重複度** — fish / nvim / wezterm / starship / macOS / Claude Code
  のいずれかを実際に使っている。使っていない環境の設定は摩擦低減に繋がらない
- **(b) 直近 6 か月以内に更新がある** — 更新が止まった dotfiles は、その人が
  今どう困っているかの情報を持たない
- **(c) 本人が日常運用している実物である** — 「dotfiles の書き方の見本」として
  作られた repo ではなく、実際に毎日動いているもの

(b) は `/survey` step 2 で毎回実測する (満たさなくなったときの扱いは
SKILL.md step 2 に書いてある)。

## dotfiles (初期 seed)

`pushed_at` は 2026-07-31 に `gh api` で実測した値。

| 巡回先 | 重複するスタック | 最終更新 (実測時点) |
|---|---|---|
| [folke/dot](https://github.com/folke/dot) | nvim (lazy.nvim 作者), macOS | 2026-04-17 |
| [craftzdog/dotfiles-public](https://github.com/craftzdog/dotfiles-public) | nvim, wezterm, macOS | 2026-02-20 |
| [mattmc3/dotfiles](https://github.com/mattmc3/dotfiles) | fish, macOS | 2026-07-11 |

**除外の記録** (再調査の重複を避けるため残す):

| 候補 | 除外理由 |
|---|---|
| mathiasbynens/dotfiles | 基準 (b) 未達 — 最終更新 2024-08 |
| jorgebucaran/cookbook.fish | 基準 (b) 未達 — 最終更新 2023-09 |
| sindresorhus/dotfiles | repo が存在しない (404) |
| jdx/dotfiles | repo が存在しない (404) |

## 仕様変更

| 情報源 | 見るもの |
|---|---|
| [Claude Code CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) | hook / skill / settings / permissions の仕様追加・変更 |
| [Claude Code リリースノート](https://docs.claude.com/en/release-notes/claude-code) | CHANGELOG に出ない運用面の変更 |
| [fish-shell releases](https://github.com/fish-shell/fish-shell/releases) | 構文・組み込み関数の変更 (設定の書き換えが要るもの) |
| [neovim releases](https://github.com/neovim/neovim/releases) | API 変更・非推奨化 |
| [wezterm releases](https://github.com/wezterm/wezterm/releases) | 設定スキーマの変更 |
| [starship releases](https://github.com/starship/starship/releases) | モジュール追加・設定キーの変更 |

## トレンド

| 情報源 | 見るもの |
|---|---|
| [This Week in Neovim](https://dotfyle.com/this-week-in-neovim) | プラグイン・設定の動向 |
| [Homebrew formulae の新規追加](https://formulae.brew.sh/analytics/install/30d/) | 実際に使われ始めている CLI |

トレンドは「話題になっているか」ではなく「**この環境の摩擦をどう減らすか**」で
評価する。1 文で書けないものは `/survey` step 3 の表に載せない。
