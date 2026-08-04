---
name: dev
description: 1 開発サイクル (タスク着手 → 実装 → レビューループ → PR 作成) を 1 コマンドで実行する umbrella skill。issue 番号・自由文・引数なし (HANDOFF 継続) のいずれでも起動できる
---

タスクの受付から PR 作成までを 1 コマンドで実行する。人間のゲートは
「非自明タスクの plan 承認」・「/pr の finding 分類承認 ((b)/(c) が
1 件でもあるとき、/pr skill が発火)」・「PR の merge」の 3 点。その間の
simplify / codex-review / pr の個別指示と code-reviewer サブエージェント
呼び出しを不要にする。

サイクル全体: `/dev` → (plan 承認) → 実装 → レビューループ → PR 報告で停止
→ user が GitHub 上でレビュー & merge → `/next` → `/clear` → 次の `/dev`。

## Steps

### 1. タスク受付 (引数で分岐)

- **issue 番号** (`/dev 42` / `/dev #42`): `/issue` skill の手順に従う
  (issue 取得 → state 確認 → ブランチ作成 → 実装 plan 提案)。
  `/issue` が plan を提案した時点で step 2 の判定に合流する
- **引数なし**: プロジェクトルートの `HANDOFF.md` を読み、「未完了・次に
  やること」の最優先タスクを対象にする。HANDOFF.md が無い・残タスクが
  曖昧な場合はタスク内容を user に確認して停止する
- **自由文** (`/dev <タスク記述>`): 記述内容をそのままタスクとする

いずれの場合も、main 以外にいる・uncommitted changes がある場合は
状況を報告して user の指示を待つ (勝手に stash / checkout しない)。
main にいる場合は `feature/` `fix/` `refactor/` `docs/` + 英語小文字ハイフン
のブランチを作成する。

#### 1a. backlog の煙探知 (opt-in・repo ごと・停止しない)

リポジトリルートに `.claude/backlog.conf` があれば読む (無ければこの節は
まるごと skip。`.claude/stop-gate.conf` と同じ opt-in 方式)。書式は
`KEY=VALUE` の 1 行ずつ、`#` 始まりはコメント。

`BACKLOG_CAP` があれば
`gh issue list --state open --limit 100 --json number --jq 'length'`
(`--jq` は `--json` 無しでは `cannot use --jq without specifying --json` で落ちる)
で実数を取り、**超過していたら 1 行報告するだけで着手は止めない**。

上限そのものは在庫の症状を抑える対症療法であり、原因ではない。ここでの
役割は**煙探知機**に限る: 超過は「step 5 の起票ゲート (目的接続 / Tier 分類)
が機能していない」というサインなので、棚卸しの前に**入口が壊れていないかを
先に疑う**。棚卸しを提案するのは user が求めたときだけ (**勝手に close しない**)。

### 2. Plan チェックポイント (非自明タスクのみ停止)

タスクが以下のいずれかに該当する場合、**実装前に** plan (変更ファイル・
実装手順・考慮点) を提示して user の承認を待つ:

- 新機能・新ツールの追加 (既存の修正ではない)
- 設計判断の分岐がある (複数の実装方式から選ぶ必要がある)
- hooks / settings / security 境界に触れる
- 変更見込みが 3 ファイル超、または既存挙動を変える

該当しない場合 (バグ修正・テスト追加・doc 修正・機械的リファクタ等の
自明タスク) は plan を 1-3 行で示すだけで停止せず実装に進む。
判断に迷ったら停止する側に倒す。

#### 2a. Pre-plan investigation (非自明タスクは必ずメインで実施)

Fable 委譲の前に、**メインが以下を調査して事実を確定させる**。Fable は
fresh context なので、渡す事実が不足すると hallucination で埋まる。委譲の
利益 (self-preference bias 回避・推論深度) は事前調査が土台。

1. **タスク面の把握**: issue 本文 / HANDOFF 記述 / 自由文の要件を書き出す
   (受け入れ条件・スコープ外を明示)
2. **影響範囲の特定**: 変更対象ファイル候補を Grep で列挙 (規模の当たり
   をつける)
3. **既存実装の確認**: 対象ファイルの該当箇所を Read。似た機能が既に
   ないか adjacent ディレクトリ (共有 utility / helper) も Grep で確認
   (再実装の予防)
4. **制約の抽出**: repo CLAUDE.md / 関連 skill / 既存 test の慣行を確認
   (repo 特有ルールに違反する plan を出さないため)
5. **不確実性の記録**: 調査中に判明した不明点 / 選択肢を列挙 (Fable に
   「この分岐で判断してほしい」と明示できるよう)

上記の成果物 (調査済み事実 + 制約 + 不確実性リスト) を Fable への prompt
に **同梱**する。Fable は repo を再探索せず、渡された事実だけで plan を
組み立てる (再探索コスト回避 + 事実整合)。

自明タスクではこの 2a はスキップ可 (1-3 行 plan と一体でメインが処理)。

#### 2b. Plan 立案の Fable 委譲

**Plan 本文の立案は Fable サブエージェントに委譲する** (メイン Opus が
自前で書かない)。self-preference bias を避けつつ推論深度を上げるため。
呼び出し方:

```
Agent(
  subagent_type: "general-purpose",
  model: "fable",
  description: "Plan for <task>",
  prompt: "<step 2a の成果物一式 (タスク要件 / 影響範囲 / 既存実装の
    該当箇所 / repo 制約 / 不確実性リスト) を渡し、変更ファイル・
    実装手順・考慮点だけを返させる。repo の再探索は不要、実装や質問は
    しないと明記する>"
)
```

メインは返ってきた plan を repo 慣行と照合し、そのまま (または軽く補正
して) user に提示する。自明タスクの 1-3 行 plan は委譲コストが上回るため
メインのまま。

### 3. 実装

plan に沿って実装し、コミットする (コミット規約は CLAUDE.md 準拠)。
実装中に plan と食い違う事実が見つかったら、乖離が大きい場合は
user に報告して指示を待つ。

### 4. レビューループ (既定 最大 2 周 / live 実害があれば user 承認で延長)

#### 4-0. 停止条件と finding の三層分類 (最優先で読む)

**ループの終端は「指摘が出なくなること」ではない。「Tier1/Tier2 が残って
いないこと」である。** LLM レビュアーは recall 最適化されており、コードの
品質と関係なくほぼ一定レートで finding を出す (実務報告では false positive
60-80%)。したがって「指摘ゼロ」を終端にすると、停止はコードの状態ではなく
レビュー回数の関数になり、原理的に到達しない。

各 finding を受け取った時点で三層に分ける:

- **Tier1** — 壊れる: 実行時エラー / データ破壊 / 権限・秘密情報の漏れ /
  ガードが実際に効いていない。**必ず fix する**
- **Tier2** — 構造的欠陥: 実際に誤った結果を返す経路がある / 検証が
  vacuous pass する / 計測できる性能劣化。**fix するか、実害を 1 文で
  書いて step 5 の三択に載せる**
- **Tier3** — スタイル・好み・将来の網羅性向上 (「今は壊れていないが将来
  こう変更されたら検出できない」型) ・micro-optimization。
  **fix しない。issue にもしない。記録もしない** (分類表にも載せない)

**例外: この変更自体が live 環境に持ち込んだ実害は、周回数に関わらず即 fix
する。** `claude/hooks/` `claude/settings.json` `claude/skills/` 等は
`~/.claude/` への symlink 経由で **commit も merge も待たずに有効になる**
(memory `project_dotfiles_env_quirks`)。したがって「hook が固まる」
「Bash tool が止まる」型の finding は、**PR を止めても user 環境の問題が
解決しない**。2 周上限は発散防止のための制限であって、自分が壊した環境を
放置する根拠ではない。上限を超えて回すときは user 承認を取り、構造化ログの
`round=` は 3 以降も連番で出す (`applied` は実数)。

実例: issue #267 で、2 周目のレビューが「開発中の hook が無限ループする」
finding を出した。規約どおり三択へ流すと、Bash tool が止まる状態のまま
PR に進むところだった (実際は user 承認を得て 6 周まで延長)。

Tier3 を記録しないのは情報を捨てているのではない。同じ指摘は次のレビューで
また出るので、実際に問題化したときに改めて拾える。逆に記録すると、消化
されない在庫として残り続ける。

この三層分類は finding への**対応**だけでなく、こちらから**生成するもの**
(eval / docs 追記 / skill 追加) にも適用する — Tier3 相当は生成しない
(基準の本体は AGENTS.md「コード品質」節)。

#### 4-1. レビュー隊列 (変更の性質で厚みを変える)

- **`claude/skills/` `codex/skills/` `*/evals/` `tests/` `docs/` `.github/`
  のみを触る変更**: **`/simplify` 1 回のみ**。code-reviewer は
  呼ばない。これらの機構は欠陥が次のセッションで実際に顕在化する自己修正性
  がある一方、機構へのレビューが機構改善 finding を生む正のフィードバックが
  backlog 増加の主因だったため
  - **例外 (フル隊列)**: `claude/hooks/` `agents/hooks/`
    `codex/hooks/` `claude/settings.json` `codex/config.toml` など
    **security 境界・秘密情報・破壊的操作のガードに触る変更**。ここは
    誤りが静かに防御を無効化するので厚さを維持する
- **それ以外の変更** (`fish/` `nvim/` `wezterm/` 等の実際の設定、
  `scripts/link.sh` のような配置ロジック): 下記のフル隊列

以下を順に実行する。**修正が入ったら再度 1 周目から回す (上限 2 周)**。
2 周目でも新規指摘が出た場合は残りを fix せず記録し、step 5 の /pr の
fix-or-issue-or-dismiss ポリシーに委ねる (発散防止)。

1. `/simplify` — 指摘を apply (skip 判断は理由を記録)
2. `code-reviewer` サブエージェントを Agent tool (`subagent_type:
   "code-reviewer"`, **`model: "fable"`**, `run_in_background: false`) で
   起動する。返る `[Critical|Warning|Suggestion]` 指摘をメインが fix
   (Agent は read-only)。fix しない判断をした finding は理由を記録
   (step 5 の /pr の fix-or-issue-or-dismiss ポリシー対象になる)。
   `model` を明示するのはメイン (Opus 世代) と別系統に寄せるため
   — 規約と、frontmatter ではなく呼び出し側で指定する理由は
   `docs/ai-operations.md` §1
3. プロジェクトのテストスイート (`make test` 等) — fail したら直す
4. コミット (レビュー修正分)

codex-review は step 5 の /pr が risk tier に応じて実行するため
ここでは呼ばない (重複実行の回避)。

#### 構造化ログ (周回数と完了状態の機械検証用)

各 round の開始時と終了時に、以下を **行頭から (テンプレートの `N`
は整数値に展開して) この形式** で応答テキストに出力する (grep で検証
されるため前後に装飾を付けない):

```
[dev/review-loop] round=N phase=start head=<git HEAD の短縮 SHA> dirty=<0|1>
[dev/review-loop] round=N phase=end applied=N status=<complete|continue|cap-reached> head=<sha> dirty=<0|1>
```

- `N` (round) は 1 以上の整数。既定は 1 または 2 で、**user 承認で上限を
  延長した場合 (4-0 の「live 環境に持ち込んだ実害」例外) のみ 3 以降も
  連番で出す**
- `head=<sha>` は当該時点の `git rev-parse --short HEAD` (7 文字前後)
- `dirty=<0|1>` は当該時点で `git status --porcelain` の出力が空なら
  `0`、あれば `1` (uncommitted changes の有無)
- `applied=N` は当該 round で apply した指摘の件数 (fix commit 数ではなく
  /simplify / code-reviewer の指摘のうち fix した件数の合算、単位や
  カンマを付けずに整数のみ)
- `status=` の 3 値:
  - `continue` — この round で修正が入り次 round へ再周回する
    (round=1 の end でのみ出現しうる、round=2 では出さない)
  - `complete` — 指摘 0 で loop 正常終了 (round=1 で 0 指摘完了も含む)
  - `cap-reached` — round=2 で残指摘があるが 2 周上限のため fix せず
    step 5 (/pr) の fix-or-issue-or-dismiss へ引き渡す
- **round=2 の判定基準**: 「発散防止のため 2 周目では新規指摘を
  fix しない」規約 (本 step 冒頭) に従い round=2 の `applied` は必ず
  `0`。status は `complete` (残指摘 0) か `cap-reached` (残指摘あり)
  の 2 択で、`continue` は取らない。
  **上限を延長した場合はこの限りでない** — 延長後の round は fix を伴う
  ので `applied` は実数、status も `continue` を取りうる。延長の承認を
  得た turn がその根拠になる
- **fix コミットを作らない round の head/dirty 不変**: 「発散防止のため
  fix しない」規約に従う round (上限延長の無い round=2 + round=1 で
  0 件完了ケース)
  では、`phase=start` と `phase=end` の `head=` と `dirty=` がそれぞれ
  同一でなければならない (両方 `0` または両方 `1`)。Edit / Write tool
  call マーカーでは Bash 経由の変更を取りこぼすため head + dirty の
  同値比較で全経路 (Bash / apply_patch / sed 含む) の変更混入を検出
  する。`dirty=0` を強制しないのは、sandbox の制限で解消できない
  pre-existing な untracked 残存により `dirty=1` スタートが起こり得る
  ため (start と end で同一であることだけを見る)。**既知の非検出**:
  `dirty` は二値なので、`dirty=1` で始まった round に新規の uncommitted
  change が加わっても `1 → 1` のまま通る (完全に見るには
  `git status --porcelain` の checksum 比較が要る)

### 5. PR 作成

#### 5a. 学びの昇格チェック (事故があったサイクルのみ)

このサイクルで**実際に事故 (誤った実装・手戻り・防御のすり抜け) を踏んだ
場合に限り**、再発防止として repo に置くもの (CLAUDE.md / `claude/rules/` /
skill) をこの PR に含める。**事故がなければまるごと skip する** (4-0 と
同じ理由で、探せば必ず出るが出たことは学びの証拠ではない)。同一 PR に
載せるのは、昇格の根拠が diff とレビュー記録に揃っているうちに固めるため。

昇格候補があれば **user に提示して承認を得てから** 実装 → コミットし、
同じブランチに載せる (勝手に書き換えない)。承認が得られなければ載せない。

**分割する例外** (この PR に載せず、別 PR / issue に切る):

- 昇格対象が settings / hooks / security 境界に触れ、この PR の risk tier や
  レビュー範囲を押し上げる場合
- 昇格内容に設計上の議論が必要で、この PR の merge を待たせてしまう場合
- 対象が memory (`~/.claude/projects/.../memory/`) の場合 — repo 外なので
  PR に載らない。承認後その場で反映する

merge 後に初めて判明した学び (merge 手順 / CI / 運用で分かったもの) は
`/next` の step 4 で拾う。

#### 5b. push と PR 作成

レビューループの最終 commit 直後にまず `git push origin <branch>` で
push し、CI 実行と後続の evidence 組み立て・issue 起票を並走させる
(CI green 確認ゲート自体は維持)。
その上で `/pr` skill を実行する (risk 分類 → tier 別 codex-review →
fix-or-issue-or-dismiss → evidence 付き PR 作成まで /pr の手順に従う)。

### 6. 停止

PR URL と evidence 要約を報告して**停止する**。merge はしない
(user が GitHub 上でレビューして merge するのが監視ゲート)。
merge 後の後続は `/next` skill が担う。

## 注意

- このスキルは既存 skill (issue / pr) と `/simplify` slash command と
  code-reviewer サブエージェントの orchestrator であり、各 skill の
  手順を上書きしない。矛盾がある場合は個別 skill の記述が優先
- レビューループの上限 2 周は発散防止の意図的な制限。上限到達で残った
  finding は /pr の fix-or-issue-or-dismiss ポリシー (fix / issue 起票 / 対応
  しない の三択、user チェックポイントを挟む) で必ず行き先が付くため、
  黙って消えることはない。**ただし三択は「PR に載せるかどうか」を決める
  仕組みなので、既に user 環境で起きている不具合には効かない** — 適用外の
  条件は step 4-0 の例外が正本
- PR 作成は明示指示待ちの原則 (memory) の例外: `/dev` の起動自体が
  PR 作成までの明示指示とみなす
