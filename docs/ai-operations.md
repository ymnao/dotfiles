# AI 運用ガイド

人間(自分)向けの運用ドキュメント。モデルが毎セッション読む AGENTS.md には
入れない(コンテキスト節約のため。確実に実行させたいルールは hook に、
毎セッション必要な最小ルールだけ AGENTS.md にある)。

## 1. モデル運用(役割分担)

AGENTS.md「モデル分担ルール」節の最小規範を、こちらで役割・モデル対応・
根拠込みに詳細化する。

**この表のモデル列は世代レベルで書く。ポイントバージョン(`4.7` 等)を正規の
記述にしない** — 上流がモデルを差し替えると、誰も操作しないまま表だけが古くなる
(実際に 2 世代ぶんずれた)。具体的な版数は「実測値 + 測定日」の注記としてのみ
書く(`claude/rules/shell.md` の「コメントに書く外部環境の事実は実測して測定日を
添える」と同じ扱い)。分けているのは*外れたときの壊れ方*なので、**外れたら
fail-loud になる場所の版数固定はこの規約の対象外**(eval 実行手順の
`claude --model claude-sonnet-5 -p ...` は ID が失効すればコマンドが落ちるので、
再現性のためむしろ固定すべき)。危険なのは外れても何も落ちない*方針の記述*だけ。

**特定バージョンを避けたい判断はここに理由と日付つきで書く。** 世代レベル記述は
版数の陳腐化を防ぐが、「この版は使わない」という**将来への制約**を書く場所を
奪ってはいけない。旧版にあった「Opus 4.8 は使わない」は、除外対象の世代自体が
現行でなくなったため失効として削除した(理由が記録されておらず引き継げなかった
— 次に書くときは理由を必ず添えること)。現在有効な除外指定は無い。

| 役割 | モデル | effort | 用途 |
|---|---|---|---|
| メイン(統括・意思決定) | Opus 世代 | high(難所は xhigh) | 全体制御・decisions・並列調整・軽 verify・PR 作成 |
| **plan 立案**(非自明タスク) | **Fable 世代** | - | `/dev` step 2 の変更ファイル・実装手順・考慮点の立案。self-preference bias 回避 + 推論深度確保のためメイン Opus からサブエージェント委譲 |
| 実装ループ(詳細 plan あり) | Sonnet 世代 | high(難所は xhigh) | ファイル/関数/追加行の意図まで指定された実装、機械的 refactor、テスト追加 |
| 並列 fan-out(中軽度並列) | Sonnet 世代 | high | /simplify の観点別 finder、多点調査 |
| 独立第二意見(別モデル系統) | Fable 世代など | - | fresh context のレビュー、難しい設計判断、cascade でメインが疑わしいと判定したときのエスカレーション先 |
| 探索・情報収集 | Haiku 世代 | - | 軽い調査・ファイル探索 |

**実測 (2026-08-04 / `claude` 2.1.220)**: メインは Opus 5 (`claude-opus-5`)、
`code-reviewer` サブエージェント(frontmatter は `model: opus`)も Opus 5 に
解決された(2026-08-03 の測定から変わらず)。根拠はどちらもセッションの
システムプロンプトが報告するモデル名で、**alias の解決先を実行基盤の外から検証した
ものではない**。なお `opus` の指す先が Opus 5 になったのは 2.1.219(公式
CHANGELOG の "Added Claude Opus 5 (`claude-opus-5`), now the default Opus
model" より。バイナリからは観測できないので出所は CHANGELOG)。この repo は
alias 運用を採っているため**設定の変更は不要だった**(下記のとおり alias 運用は
意図)。この表は強制力を持たない — `claude/settings.json` にモデルを指定する
フィールドは無く(`effortLevel` のみ)、切り替えは `/model` か CLI 既定に依存する。
したがって表と実挙動の一致は、この実測でしか確かめられない。

`claude/agents/code-reviewer.md` の `model: opus` は **alias 運用が意図**で、
ID 直書きにはしない — alias は上流の世代交代に追随するので表の「Opus 世代」の
内側に収まる。逆に ID を固定すると世代が上がったときレビュアーだけが旧世代に
取り残される(ドリフトの向きが変わるだけ)。

**「生成者とレビュアーは同一モデル系統にしない」への対応 — 呼び出し側で寄せる**。
下の「根拠」節と `agents/AGENTS.md` が掲げるこの規約に対し、frontmatter の
`model: opus` のままだとレビュアーがメイン(Opus 5)と同一系統になる。そこで
`/dev` step 4-1 の `code-reviewer` 起動は **Agent tool の `model: "fable"`
パラメータで明示的に別系統へ寄せる**。

**なぜ frontmatter ではなく呼び出し側か(2026-08-04 実測、`claude` 2.1.220)**:

- **Agent tool の `model` パラメータは効く** — `subagent_type: "code-reviewer"`
  + `model: "fable"` で起動した subagent は `Fable 5 / claude-fable-5` と自己申告した
- **frontmatter の `model:` はセッション内では検証できない** — `model: fable` に
  書き換えて起動しても `Opus 5`、対照として確実に有効な alias である
  `model: sonnet` に変えても `Opus 5` のまま。つまり**agent 定義はセッション開始時に
  読まれ、同一セッション中の書き換えは反映されない**。よって「`fable` が受理された
  のか、黙って既定にフォールバックしたのか」は**再起動しないと判別できない**
- 判別できないまま frontmatter を `fable` にすると、受理されなかった場合に
  **規約違反が「対応済み」の見た目のまま残る**。呼び出し側パラメータは実測で
  効くと分かっているので、そちらに倒した(「確認できないなら厳しい側に倒す」
  — `claude/rules/shell.md`)

frontmatter は `model: opus` のまま据え置く。呼び出し側が指定しなかったときの
既定として妥当で、alias 運用の方針とも整合するため。

**一般則: `model` を指定しない呼び出しは frontmatter 既定の `opus` に落ちる**。
つまり **`code-reviewer` の呼び出し口のうち**別系統に寄っているのは
`/dev` step 4-1 経由だけで、それ以外
— `claude/skills/adversarial-review/`(2 体を競わせる設計。SKILL.md 自身が
「同一モデル内で網羅性を上げる」道具と位置づけているので Opus 系のままで整合)、
`claude/skills/dependabot-bulk/`、`codex/skills/pr/` が指示する Claude 側
レビュー、および skill を経由しない ad-hoc 起動 — は**すべて Opus 系のまま**。
呼び出し口を増やすときは `model` 指定の要否をその場で決める。

**`codex-review` が恒常的に使えなくなったときは即座に見直す** — cross-vendor の
第二意見という緩和が消えるため。`/pr` は codex 不能時に Fable 系サブエージェントで
代替する設計なので、そのフォールバックが常態化していたらこれに当たる。

- 切り替え: `/model`、Agent ツールの `model` パラメータ
  (例: `Agent(subagent_type: "general-purpose", model: "sonnet", prompt: ...)`
  独立第二意見は `model: "fable"`)
- 原則: **浅い推論を見たらプロンプトを工夫する前に effort を上げる**
  (公式推奨。モデル変更より effort が先のレバー)
- レビュー系タスクで下位モデルを使うときは「重要度でフィルタせず全部
  報告 → 後段でフィルタ」の 2 段にする(literal 特性への公式対策)

### 根拠(業界 BP)

- **生成者とレビュアーは同一モデル系統にしない**: self-preference bias
  で自己生成物を過大評価する(arXiv:2410.21819)。Anthropic ネイティブの
  reviewer には Fable のような別系統を、あるいは cross-vendor(codex-review
  等)を差す
- **並列 fan-out は中モデル + orchestrator パターンが上位モデル単体より
  高性能かつ安い**: Anthropic の multi-agent research system の実測で
  Opus lead + Sonnet subagent が単体 Opus を 90.2% 上回った
- **cascade 型エスカレーション**(中モデル実装 → メイン軽 verify → 疑わし
  ければ第二意見)が静的割り当てよりコスト最適(FrugalGPT 系サーベイ)
- **委譲は「自己完結タスク → 結果を返す型」に限る**: 逐次質問往復は
  fresh context の利点を消すのでメインで拾う

## 2. モデル世代移行チェックリスト

alias の指す先が変わったとき(上流の世代交代、`/model` での恒久的な切り替え、
役割ごとの割り当て変更)に実施する。

**限界を承知で使うこと**: このチェックリストは*気づいた後*の手順で、
**気づく仕組みではない**。今回のドリフトの実体は「誰も操作していないのに
上流が黙って差し替え、2 世代ぶんずれた」であり、その検知手段は無い
(実行中のモデルは `make test` から観測できないので、テストにすると
vacuous pass する)。世代レベル記述にしたことで**ズレの発生頻度**は下がるが
(1 世代の差では表現上ずれない)、上流差し替えを観測していないという
**根本原因は残っている**。実測注記の測定日が古いことだけが手がかり。

- [ ] `claude/settings.json` の `effortLevel` を見直す(現行 "high"。
      高難度タスクは xhigh が公式推奨。まず high 維持
      + 難所で引き上げの運用から始め、質が足りなければ既定を上げる)
- [ ] 現存する skill eval(事故 pin のみ。一覧は
      `claude/skills/codex-review/evals/README.md`)を実行し、壊れた skill を
      特定して修正する
- [ ] `make test`(hook 回帰テスト込み)を実行して基線を確認する
- [ ] 最初の 1 週間、レビュー指摘の見逃し・skill の手順飛ばしを意識的に
      観察し、気づきを CLAUDE.md / skill に反映する(下記 3)
- [ ] 移行元の世代に固有の記述が設定に残っていないか確認する
      (例: `grep -ri fable claude/ codex/ agents/`)
- [ ] **§1 の実測注記を更新する**(モデル名・ID・測定日)。ズレに気づく
      唯一の手がかりなので、ここを更新しないと世代レベル記述の意味が薄れる
- [ ] **agent frontmatter が完全なモデル ID / 別 alias を受け付けるか試す**
      (実測根拠は §1)。`model:` を書き換える → **Claude Code を再起動する**
      → `code-reviewer` に自分の実行モデル名を報告させる。**再起動が要る** —
      同一セッション中の書き換えは反映されない。受理されると分かったら §1 の
      「呼び出し側で寄せる」判断を再検討し、結果を §1 に反映する

## 3. 失敗駆動の設定改善(Boris Cherny 方式)

- モデルの誤りを見たら、その場の再プロンプトで流さず
  **CLAUDE.md か該当 skill に修正を書き込む**(将来の全セッションに効く)
- 追記の品質基準: 検証可能な形で書く(「注意する」ではなく
  「X の場合は Y する」)。定期的に各行へ
  「この行を消したらミスするか?」を問い、No なら削除する
- 200 行を超えたら skill / hook への移譲を検討する

## 4. セッション運用の定石

- **開発サイクルの定型は 2 コマンド**: `/dev`(受付 → plan 承認(非自明のみ)
  → 実装 → simplify / code-review / テストのレビューループ → /pr)→ user が
  GitHub で merge → `/next`(merged 確認 → pull → 学び昇格チェック →
  handoff → 次候補提示)→ `/clear` → 次の `/dev`。人間ゲートは
  「非自明タスクの plan」・「/pr の finding 分類承認 ((b)/(c) が 1 件でも
  あるとき発火)」・「merge」の 3 点。レビュー finding は
  fix-or-issue-or-dismiss ポリシー(fix / issue 起票 / 対応しない の三択。
  「対応しない」は許可 3 条件 + user 承認 + PR body 記録が必須、未起票 defer は
  verify-ci-before-pr hook がブロック)で次セッションへの暗黙持ち越しを防ぐ
- 無関係なタスクの間で `/clear`(コンテキストを引きずらない)
- **2 回訂正して直らなければ `/clear`** し、学んだことを盛り込んだ
  プロンプトで新セッションを始める(訂正が蓄積した長セッションより、
  良いプロンプトの新セッションがほぼ常に勝つ)
- 探索・調査はサブエージェントに委任してメインのコンテキストを守る
- メモリ運用: 1 ファイル 1 教訓、先頭に 1 行サマリ、誤りと判明したら削除

## 5. MCP / skill / プラグイン追加の審査基準

新しいツールを入れたくなったら、この順で検討する:

1. **CLI で代替できるか**(gh, jq, 専用 CLI)→ CLI を使う
2. **skill 化できるか**(頻用ワークフロー・手順知識)→ skill を書く
3. どちらも不可(認証付きライブ接続等)のときのみ MCP
4. 導入審査: 出所の確認(公式 / 著名作者か)・中身を読む(skill は
   Markdown なので全文監査できる)・最小権限・lethal trifecta
   (秘密データ+信頼できないコンテンツ+外部送信の同時成立)を作らないか
5. 半年ごとに棚卸し: 「今のモデル性能でもまだ必要か?」を問う
   (例: sequential-thinking MCP は adaptive thinking 内蔵化で 2026-07 に削除済み (PR #65))

**審査結果の置き場**: 実測を伴う審査は §10 に実測節を立てて根拠をそこに置き、
§9 の表には**結論と実測節への参照だけ**を書く。§9 のセルに監査の内訳を書き
込まない — 表は一覧性が価値なので、根拠を詰めると読めなくなる。実測を伴わない
(まだ審査対象になっていない) 見送りは、従来どおり §9 の理由欄で完結してよい。

## 6. レビューと理解の保ち方

- PR の証拠セクション(pr skill が自動生成)を読む。diff 全精読は
  高リスク PR のみ(explain-the-diff ウォークスルー付き)
- 原則: **理解できないコードはマージしない**(差し戻すか説明させる)
- AI レビュー(codex-review / code-review)は信頼できる diff 専用。
  外部コントリビュータの PR に無条件で自動レビューを走らせない
  (prompt injection 前提の運用)
- 高リスク変更(セキュリティ境界・hooks・認証・リリース前最終確認)の
  merge 前は `/adversarial-review`(競争的 2 体レビュー)を使う

## 7. メモリ運用(auto memory)

auto memory(`~/.claude/projects/<project>/memory/`)は各セッション起動時に
MEMORY.md 先頭 200 行が自動ロードされる。

- 1 ファイル 1 教訓。description(recall の判定に使われる)を必ず書く
- 週 1 回か大きな作業の区切りで `/consolidate-memory` を実行する
  (重複統合・陳腐化した記述の削除・インデックス修復)
- **機微情報(トークン・社内情報・個人情報)を書かない**。メモリは
  gitignore もされず secretlint も通らない領域
- **メモリはマシン間で共有されない**。マシンをまたぐ引き継ぎはメモリに
  頼らず、リポジトリ内ファイル(HANDOFF.md 等)で行う(/handoff skill)
- 繰り返し必要になる知識はメモリに置いたままにせず、`~/.claude/rules/`
  (ファイル種別限定)か CLAUDE.md(常時)へ昇格させる。メモリは
  「昇格前の受け皿」と位置づける

## 8. permissions の定期見直し

- 移行後にプライベート PC で数セッション運用したら
  `/fewer-permission-prompts` を実行し、提案された allowlist を
  **1 件ずつ手動レビューして** `claude/settings.json` に反映・コミットする
  (提案の丸呑みはしない。書き込み系・ネットワーク系は原則入れない)
- 以後は「同じ許可プロンプトに 3 回答えたら allowlist 追加を検討」を目安にする

## 9. 導入を見送った機構(再評価条件つき)

先回りで入れず、条件を満たしたら再評価すると決めたもの。初期の 8 件は
2026-07-03 の検討(HANDOFF.md 候補 1〜10)由来だが、**その後に足した行もある**
(日付は行ごとの見送り理由に書く)。

**導入済みツールの一部機能だけを見送った場合もここに書く** — 表の単位は
「ツール」ではなく「見送った機構」。本体を入れたことが、その拡張まで
審査済みであることを意味しないため(実例: herdr の 3 行)。

**harness に標準搭載されていて導入ステップ自体が存在しないものも、
運用に採用しないと決めたならここに書く**(実例: Workflow tool の行)。
「使えること」は「使うと決めたこと」ではないため。

| 機構 | 見送り理由 | 再評価条件 |
|---|---|---|
| GitHub Actions 連携(claude-code-action) | API 従量課金が必要(x20 定額の外)。ローカルレビューと重複。prompt injection 前提の運用が必要 | 他者コントリビュータのいるリポを持ったとき |
| Agent teams | 実験的で既知制限が多い(再開不可・ネスト不可等)。サブエージェントで足りる | GA になり、並列レビュー等で実需が出たとき |
| opusplan | plan mode を計画の境界として使っていない(セッション+仕様書で分離する運用)。/model で随時有効化できる | plan mode 中心の運用に変わったとき |
| Superpowers(obra/superpowers) | 公式マーケットプレイス外で全文監査が必要。既存 skill 群と思想が重複。更新追従がない | 同種の困りごとが 3 回起きたとき、または公式マーケットプレイス入りしたとき(その skill だけ監査して取り込む) |
| keybindings カスタマイズ | 現時点で困っている操作がない | 操作の不満が具体化したとき |
| Stop hook 駆動の review 強制ループ(claude-review-loop 系) | /dev 内の有界レビューループ(上限 2 周)で足りる。無限ループ対策(`stop_hook_active` guard)が必要になり、停止タイミングの監視性も下がる | /dev 運用でレビュー飛ばしが実際に起きたとき |
| herdr の agent skill(`herdr --skill`) | (2026-08-07 / #276)**動かないので入れない** — Bash tool の sandbox が AF_UNIX を遮断するため、skill を置いても `herdr pane run` 等が成立しない。§5 の審査の内訳と実測は §10「[herdr socket API と各防御層の関係](#herdr-socket-api-と各防御層の関係--実測結果)」 | ペイン内 Claude Code で sandbox の遮断が破れていると判明したとき(そのときは skill の採否より先に遮断経路の封鎖を検討する)、または `sandbox.excludedCommands` へ herdr を足す提案が出たとき |
| herdr の plugin 機構(`herdr plugin install OWNER/REPO`) | (2026-08-07 / #276)GitHub から第三者コードを取得して herdr のランタイム内で動かす機構。**現時点で入れたい plugin が具体的に無く、§5 の出所確認・全文監査を通す対象が存在しない**。この repo は「困りごとが起きてから 1 件ずつ審査する」側なので、機構そのものの可否を先に決めない | 具体的に入れたい plugin が特定されたとき(そのとき **その 1 件だけ**を §5 で審査する) |
| herdr の codex 統合(`herdr integration install codex`) | (2026-08-07 / #276)**前提が未確認なので着手しない** — herdr ペインで codex を使う運用が実際にあるかを確認していない(現状の想定は Claude Code の常用)。加えて codex は hook を `trusted_hash` で承認するので TUI での再承認が要り、「ファイルを 1 つ増やす」ではなく**承認機構を動かす**作業になる。なお書き込み先の `~/.codex/herdr-agent-state.sh` は §10 の deny 対象(`config.toml` 1 ファイル)ではないので、**書き込み自体は塞がれていない** — Bash 経路は `block-dangerous-commands.sh` の `.codex` component 判定で止まるが、file 編集 tool 経路は通る(2026-08-07 に hook 単体で実測) | herdr ペインで codex を常用する運用が実際に始まったとき(その時点で `trusted_hash` の再承認をどう扱うかを先に決める) |
| Ralph loop 型の外側無人ループ(`while true; claude -p` 系) | merge ゲート・plan ゲートの人間監視を放棄することになる。2026-07-19 の検討で「パイプライン圧縮 + 人間ゲート再配置」(/dev + /next)を採用 | 完全無人で回してよい種類の反復タスク(大量 migration 等)が実際に発生したとき |
| project-artifact プラグイン(公式 marketplace) | (2026-08-05)#264 で HTML 説明ページを検討した際に比較した。「固定 template.html + light/dark + Artifact publish」という**機構は同型**だが、作るページの**種類が違う** — あちらは 1 回の update に収まらないプロジェクトのタブ付きステータスページを per-project config で継続更新し delta を報告するもの。#264 が要るのは 1 回きりの判断・説明ページで、タブ機構と refresh 運用は使わない分だけ負債になる。自作の `html-brief` skill を採用した | 複数ワークストリームを継続追跡して同じ URL を更新し続ける必要が出たとき(そのときは html-brief を拡張せず、プラグインをそのまま有効化して評価する) |
| `disableSideloadFlags`(Claude Code の managed 設定) | (2026-08-09 / #297)**実配置して実測し、見送った** — `--plugin-dir` を内部で渡す経路があり、Cowork 未使用でも Claude Code のプロセスが exit code 1 で落ちる。塞げるのは起動フラグ経路 1 本だけで `claude mcp add` / `.mcp.json` は素通り。実測とエラー全文は §10「[disableSideloadFlags — 実測して見送った](#disablesideloadflags--実測して見送った297)」 | 起動フラグ以外の経路も塞ぐ必要が出たとき(そのときは全 scope に効く `allowedMcpServers` / `allowManagedMcpServersOnly` を先に検討する)。ただし着手の可否は §10「[managed 設定は原則触らない](#managed-設定は原則触らない--判断基準は復旧に-sudo-が要るか)」の基準を先に通す |
| Context7 MCP(ライブラリドキュメント取得) | (2026-08-09 / #286)公式ドキュメントを直接 fetch すれば大半足りる。§5 の順序(CLI / skill で代替できるなら MCP を入れない)に該当 | 公式 doc の直接取得で調査が破綻するケースが 3 回起きたとき(そのときは §5 の導入審査 — 出所確認・全文監査・最小権限・lethal trifecta — を通す) |
| リポジトリ内 `.agents/memory/`(教訓のマシン間共有) | (2026-08-09 / #286)HANDOFF.md 運用と重複する。auto memory と §7 の昇格運用で足りる | HANDOFF 経由の引き継ぎ漏れが 2 回起きたとき |
| Workflow tool(skill の手順を決定的スクリプトに移す) | (2026-08-09 / #286)**harness 組み込みなので導入は済んでおり、見送っているのは運用への採用**(2026-08-09 に tool 一覧で存在を確認)。現行の skill 内 fan-out で足りており、採用すると同じ手順が SKILL.md と workflow スクリプトに二重管理になる | /adversarial-review や /simplify で見逃しが起き、その原因が並列数・検証回数のブレだと特定できたとき |

## 10. codex / Claude Code の host 実行面の防御層

codex CLI の `~/.codex/config.toml` は **sandbox 境界を越えて host 側で
任意コマンドを実行させられる設定ファイル**。`notify` は turn 終了時に
外部コマンドを起動し、`mcp_servers` / `hooks` / `shell_environment_policy` も
同様にコマンド実行や環境汚染の素材になる。sandbox 内の agent が repo 由来の
悪意ある入力(README / スクリプト / issue 本文の指示注入)に従ってこのファイルを
書き換えると、次回 codex 起動時に host 側で実行される(issue #190)。

`~/.codex` を allowWrite からは外せない — codex CLI が `sessions/` /
`history.jsonl` / `log/` / `auth.json` / `models_cache.json` /
`*.sqlite` (+ `-wal` / `-shm` サイドカー) に書き込むため。必要 subpath だけを
列挙する方式は codex 側の実装詳細で増えるパスに追随できず壊れやすいので採らない。
代わりに **攻撃面が集中している config.toml 1 ファイルを deny する**。

| 層 | 実装 | 効くもの | 効かないもの |
|---|---|---|---|
| 一次: sandbox | `claude/settings.json` の `.sandbox.filesystem.denyWrite` に `~/.codex/config.toml`(allowWrite の `~/.codex` に対する deny-within-allow) | **Bash tool 経由**の全書き込み経路(リダイレクト / write コマンド / `sed -i` / `mv`)。`cd ~/.codex && printf x > config.toml` のように hook を回避する形も止まる | **Edit / Write / MultiEdit / apply_patch の file 編集 tool には適用されない**(実測: deny 対象の `claude/settings.json` は Bash append は拒否されるが Edit tool では書き換えられた) |
| 一次: sandbox (プロジェクト配下) | 同 `denyWrite` に `~/*/**/.codex/**`(2026-08-08 追加) | home 直下 1 階層の作業ディレクトリ配下で `.codex/` を deny。ディレクトリが存在しなくても `mkdir` も `mv` (rename) も拒否される。**測れた範囲は下記節に明記** | 4 経路(home の外 / excludedCommands で sandbox ごと外れる行 / file 編集 tool / この設定自体の改ざん)。内訳と担当は下記「denyWrite のパス表記」節の末尾に 1 箇所だけ書く |
| 二次: hook (Bash) | `agents/hooks/block-dangerous-commands.sh` の「書き込み文脈 + `.codex` component」判定。**cwd 配下については `agents/hooks/guard-codex-dir.sh` も Bash matcher に配線されており**、command 文字列から token を抽出して cwd 内の `.codex/` を止める(読み取りも止まる) | tilde / `$HOME` / 絶対パス表記のいずれでも、path token に `.codex` component が現れる書き込みを block(block-dangerous 側は読み取りは allow のまま) | `cd ~/.codex && printf x > config.toml` のように **書き込み segment 側に `.codex` component が現れない形**(一次防御が担当) |
| 二次: hook (file 編集) | `agents/hooks/guard-codex-dir.sh` の 3 判定: `is_protected_project_path`(cwd 配下)/ `is_protected_home_codex_config`(`~/.codex/config.toml` 1 ファイル)/ `is_protected_home_project_codex_path`(home 配下の別プロジェクト。2026-08-09 追加 / #291) | Edit / Write / MultiEdit / NotebookEdit / apply_patch が (a) cwd 配下の `.codex/`、(b) `~/.codex/config.toml`、(c) `~/<任意のディレクトリ>/…/.codex/` 配下 を指す場合。tilde / `$HOME` / `${HOME}` / 絶対パス / `..` 経由 / 大文字表記を正規化し、**symlink はこの経路では無条件に解決**してから比較する(gate 任せだと、名前に `codex` を含まない symlink + `config.toml` 以外の leaf が素通りする。2026-08-09 に対照付きで実測して塞いだ) | `~/.codex/` 配下の他ファイル(`sessions/` / `auth.json` 等は codex CLI が正当に書くため意図的に allow)、および **home の外**の `.codex/`(`/tmp` / `/Volumes` 等。下記参照) |
| 正規の書き込み経路 | `scripts/codex-merge-config.sh` を **ユーザーが手動実行**(sandbox 外) | repo の `codex/config.toml` を正本として `~/.codex/config.toml` へマージ | — |

一次と二次が担当する経路は**意図的に非対称**。Bash 経路は sandbox が包括的に止め、
file 編集 tool 経路は sandbox が効かないので hook が止める。片方だけでは穴が残る。

**担当する経路は非対称でよいが、覆う範囲 (スコープ) は揃える。** 2026-08-08 に
一次 (sandbox) 側だけが `~/*/**/.codex/**` で home 配下の全プロジェクトへ広がり、
二次 (file 編集) 側は cwd 配下のままだったため、**cwd 外プロジェクトの `.codex/` が
どの層にも止められない**状態が生まれた(#291)。同じ不変条件を守る層のスコープが
食い違うと、経路の分業では説明できない穴になる。2026-08-09 に
`is_protected_home_project_codex_path` を足して二次側を一次側のスコープに揃えた。

- **home の外**(`/tmp` / `/Volumes` / 外部ボリューム等)は**両層とも非カバー**で、
  これは層間の非対称ではなく**共通の残余として受容している**。塞ぐと `.codex`
  component を持つ任意のパスを実質グローバル禁止することになり、他 repo を
  クローンして読む作業まで巻き込むため。issue #190 型の攻撃は「次に codex を
  起動するプロジェクト」で成立するので、実運用上の攻撃面は home 配下に集中する
- guard 内の **Bash token 判定は cwd 配下のみ**のまま(`is_protected_project_path`)。
  home 配下の Bash 経路は一次 (sandbox) と二次 (Bash) の 2 層が担当する
  (理由は上の表の「二次: hook (Bash)」行)

- 一次防御の regression は `tests/integrity/verify-settings-codex-domains.sh`
  (+ `run-integrity-selftest.sh` の tamper fixture)が assert する
- 二次防御 (Bash) の regression は `tests/hooks/block-dangerous-commands.cases.jsonl`
  の `home-codex-config-*` / `tilde-codex-config-*` ケースが pin する
- 二次防御 (file 編集) の regression は `tests/hooks/guard-codex-dir.cases.jsonl` の
  `{{HOME}}/.codex/config.toml` 系 (#190) と `{{HOME}}/other-project/.codex/` 系
  (#291) のケースが pin する(allow 側のラチェット — `sessions/` / `auth.json` /
  ドット無し `codex/` / home 外 / Bash 素通し — も含む)

### denyWrite のパス表記 — 相対は無視され、絶対 / `~` 始まりなら glob が効く

issue #289 の「保護をコマンド文字列の静的解析で担い続けるか」を決めるために、
**どの表記なら sandbox 層で書き込みを止められるか**を実測した
(2026-08-08 / Claude Code 2.1.220 / macOS Seatbelt)。表記の比較は保護対象と無関係な
`.sbxprobe-*` という名前で行い、`block-dangerous-commands.sh` の文字列検出を
経由せず sandbox 層だけを見ている。判定は exit code ではなく
**ファイルが実在するか**で行った(`touch` は拒否されても 0 を返しうる)。

**再現方法**: 実名の `.codex` を使う測定(出荷形の確認と下記「あわせて測ったこと」)は、
**Bash tool の command 文字列に `.codex` を書くと hook 側で止まる**ため、
測定手順を**スクリプトファイルに書いて `bash <path>` で起動**した
(ディレクトリ名は `D='.co'; D="${D}dex"` のように分割構築する)。
`SANDBOX_RUNTIME=1` でないと sandbox の外を測ることになるので、
スクリプト先頭でそれを検査して外なら中止させること
(一度ターミナルから直接起動して全プローブが素通りし、1 往復無駄にした)。

| `denyWrite` に書いた表記 | 直下 | ネスト | 判定 |
|---|---|---|---|
| `.sbxprobe-rel-exists`(素の相対) | 書けた | — | **効かない** |
| `./.sbxprobe-dot`(`./` 付き相対) | 書けた | — | **効かない** |
| `**/.sbxprobe-glob/**`(glob 始まり = 非絶対) | 書けた | 書けた | **効かない** |
| `/Users/…/.sbxprobe-abs-missing`(絶対・**存在しない**) | 拒否 | — | 効く |
| `~/development/…/.sbxprobe-tilde`(`~` 始まり) | 拒否 | — | 効く |
| `/Users/…/**/.sbxprobe-absglob/**`(絶対始まりの glob) | 拒否 | 拒否 | 効く |
| `/Users/…/.sbxprobe-absglob-top/*`(絶対始まりの単一 `*`) | 拒否 | — | 効く |
| `~/development/**/.sbxprobe-tglob/**`(`~` 始まりの glob) | 拒否 | 拒否 | 効く |
| `~/*/**/.codex/**`(出荷した形) | 拒否 | 拒否 | 効く |

読み取れること:

- **エントリは絶対パスまたは `~` で始まらなければならない。** 相対表記は
  `./` を付けても効かない。**エラーも警告も観測されなかった**ので、
  「設定したのに一度も効いていない」状態が緑のまま成立する
  (`requiredMinimumVersion` と同じ壊れ方。§10 の該当節を参照)
- **glob は「絶対パス / `~` で始まっていれば」効く。** 先頭が `**/` の形が
  効かなかったのは glob 非対応だからではなく、**エントリ全体が非絶対になる**ため
- **`**` は中間ディレクトリ 0 個にもマッチする。** 絶対パス始まりの
  `/Users/…/dotfiles/**/.sbxprobe-absglob/**` が、中間ディレクトリの無い
  `dotfiles/.sbxprobe-absglob` を拒否した(上表)
- **ただし `~/**/…` は `~/.codex/` を巻き込まなかった。** 当初この節は
  「`**` が 0 個にマッチするので `~/**/.codex/**` は `~/.codex/` まで deny して
  codex CLI を壊す」と書いていたが、**実測すると逆だった**
  (2026-08-08。`~/**/.codex/**` を設定した状態で、repo 直下と repo 配下ネストは
  拒否される = エントリは効いているのに、`~/.codex/<file>` は書けた)。
  **なぜ 0 個マッチが `~/` 直下では起きないのかは特定できていない**
  (`~/.codex` が allowWrite に literal で載っていることとの優先順位かもしれないが、
  切り分けていない)。機構が分からないまま codex CLI の生存を賭けたくないので、
  出荷形は `~/*/**/…` の側を採った
- **deny 対象は存在しなくてよい。** そのディレクトリを作る `mkdir` 自体が
  `Operation not permitted` になる(守りたいのは「まだ無い `.codex/` を
  作らせないこと」なので、この性質が無いと候補 1 は成立しなかった)
- **sandbox 設定はセッションを再起動しなくても反映された。** 同一セッション中に
  `claude/settings.json`(= `~/.claude/settings.json` への symlink)を書き換えた
  直後の Bash 呼び出しから deny が効いた。**この観測は「再起動が不要」と
  確約するものではない** — 反映契機を特定したわけではないので、設定変更の検証は
  引き続き再起動後にも確認する

この結果を受けて `~/*/**/.codex/**` を denyWrite に追加した。
出荷する表記そのもので (a) repo 直下・1 段・2 段ネストがすべて拒否、
(b) `~/.codex/` への正当な書き込みは通り `~/.codex/config.toml` は deny のまま、
(c) 似た名前 (`.codex-other`) と無関係なディレクトリは書ける、を確認済み。

**プロジェクトルートを列挙する形は採らなかった。** 当初は
`~/development/**/.codex/**` と書いていたが、これは本節の冒頭で
「codex が書く必要 subpath を列挙する方式は実装詳細の増加に追随できず壊れやすい」
として却下したのと**同じ構造**で、`~/work` のような新しい作業ディレクトリを
使い始めた瞬間に静かに非カバーになる。`~/*/` は「home 直下の 1 階層は何でもよい」
という形なので、ディレクトリ名を知らなくても追随する。

**home 直下 1 階層のプロジェクトも覆われる**(`*` が 1 段消費 + `**` が 0 段、という
合成)。home 直下は allowWrite 外でプローブを置けないが、**allowWrite に載っている
`~/.codex` を 1 階層目に使えば同じ合成を踏める** — `~/.codex/.codex/` の作成は
拒否された(2026-08-08)。したがって `~/*/**/.codex/**` の非カバーは
**`~/.codex` 自身だけ**で、そこは codex CLI のために意図して開けてある。

**あわせて測ったこと** (いずれも出荷形 `~/*/**/.codex/**` で。2026-08-08):

- **`mv` (rename) でも作れない。** 別名で用意したディレクトリを `.codex` に
  改名する形は `Operation not permitted`。deny が「中身への書き込み」だけを
  覆っていると、中身に一度も触れずに丸ごと配置できてしまうため確認した
- **綴りが違っても効く。** macOS の firmlink 綴り
  (`/System/Volumes/Data/Users/…`) 経由でも拒否された。deny は物理位置ではなく
  綴りでマッチするので、別綴りが回避経路にならないかを確認する必要があった
- **単一 `*` はドット始まりのセグメントにもマッチする。** `~/.cache/uv/…/.codex/`
  の作成が拒否された。含意は 2 方向で、**`~/.config/foo/` のような隠しディレクトリ
  配下のプロジェクトも覆われる**一方、**`~/.cache/uv` / `~/Library/Caches/pip` に
  展開されるパッケージが `.codex/` を含んでいると EPERM で失敗する**
  (下記の FP)

**受け入れた FP (いずれも fail-closed)**。遭遇したら**これは意図した deny**:

1. **正当な取得・展開が途中で止まる** — deny は書き込み主体を区別しないので、
   `.codex/` を同梱するリポジトリの `git clone` や、`.codex/` を含むパッケージの
   展開 (`uv` / `pip` のキャッシュ配下を含む) も同じ経路で EPERM になる。
   **中断後に部分展開が残るかは未確認** (ツール側の後始末に依るので断定しない)。
   必要なら home の外 (`/tmp` 等) で作業すること。発火例は未観測
2. **このエントリ文字列を扱う作業自体が hook に止まる** — `~/*/**/.codex/**` を
   引数に書いた書き込み系コマンド (settings をコピーして加工する ad-hoc 作業など) は
   `block-dangerous-commands.sh` の「`.codex` にマッチしうる glob」判定で止まる。
   実際にこの PR の作業中に `sed` と `jq` の 2 回踏んだ。**テスト経由では hook に
   文字列が渡らないので `make test` は緑のまま**で、手作業でだけ出る
3. **テストの一時ディレクトリが `$HOME` 配下だと `make test` が落ちうる** —
   `tests/hooks-glob/` `tests/link/` `tests/integrity/` は fixture として実体の
   `.codex/` を `mktemp -d "${TMPDIR:-/tmp}/…"` 配下に作る。`TMPDIR` が
   `~/tmp` のように home 配下を指す環境では、hook ではなく **sandbox の EPERM** で
   `mkdir` が落ちる。現在の `TMPDIR` は home 外なので発火していない

**それでも文字列解析の hook は統制から降ろせない。** 残る経路は 4 つ:

1. **home の外のプロジェクト** (`/Volumes/…` 等) — `~/*/` は home 直下を起点に
   するので届かない
2. **excludedCommands にマッチする行** — sandbox ごと外れる(次節)。
   compound 行は `guard-sandbox-exclusions.sh` が止めるが、**単独の除外コマンドに
   リダイレクトを付けた行**は unsandboxed で走るので hook だけが残る。
   このとき **cwd 配下**の `.codex/` は `block-dangerous-commands.sh` と
   `guard-codex-dir.sh` の 2 つが見る(後者も Bash matcher に配線され、
   command 文字列から token を抽出して cwd 内の `.codex/` を止める)。
   **cwd の外**については `block-dangerous-commands.sh` が唯一の防御になる
3. **file 編集 tool (Edit / Write / MultiEdit / NotebookEdit / apply_patch)** —
   sandbox が適用されない経路。`guard-codex-dir.sh` が担当する。
   **2026-08-09 (#291) までは、プロジェクト判定が cwd 配下に限定されていた**
   (`is_protected_project_path` は cwd prefix 一致で、
   `tests/hooks/guard-codex-dir.cases.jsonl` は `../other/.codex` を
   **allow として pin** していた)。この非対称は本節の変更で生じたものではないが
   (Bash 側だけが home 直下全体へ広がった結果、目立つようになった)、
   **同じ不変条件を守る層のスコープが食い違う状態**なので
   `is_protected_home_project_codex_path` を足して一次側のスコープに揃えた。
   あわせて、この経路の symlink 解決を**無条件**に変えた — パス文字列に
   `codex` が現れない symlink 経由の書き込みが、leaf が `config.toml` の
   ときしか止まっていなかった(同日、対照付きで実測)。
   **この経路で残るのは home の外だけ**(上の経路 1 と同じ範囲)
   **さらに、コマンド文字列だけを見る hook は `bash <script>` で中身を隠されると
   素通りする** — hook に渡るのは `bash /path/to/x.sh` という 1 行だけで、
   スクリプトの中身は検査されない。上の「再現方法」が使っているのはこの性質
   そのものである。これは実装の抜けではなく**文字列解析という方式の限界**で、
   sandbox が覆う範囲 (経路 1 以外) では sandbox 側が止めるが、
   **経路 1 (home の外) ではこの形が素通りする**
4. **この deny エントリ自体の改ざん** — `claude/settings.json` は
   Edit / Write tool で書き換えられる(sandbox の denyWrite は Bash 経路にしか
   効かない。表の 1 行目の実測)。エントリを消してから Bash で書く並びでは
   防御が経路 2 と同じ状態(cwd 内は hook 2 つ、cwd 外は
   `block-dangerous-commands.sh` のみ)に戻る。
   `tests/integrity/` の pin は `make test` / CI / Stop gate での**事後**検出で、
   同一ターン内の悪用には間に合わない

つまり #289 の答えは「文字列解析をやめる」ではなく、**Bash 経路のうち
sandbox が覆える範囲では統制の本体を操作境界へ移し、hook は多層防御 +
sandbox が届かない 4 経路の一次防御として残す**。

候補 2 (AST 解析) と候補 3 (allowlist 反転) は**今回は採らない**。ただし
「効かないから」ではない — **経路の本数は減らないが、経路 1 / 2 / 4 の残余防御の
精度には効く**(いずれもコマンド文字列を経由するため)。経路 3 (file 編集 tool) には
原理的に届かない。採らない理由はコスト比で、`docs/ai-operations.md` §5 の
ツール追加審査(依存とレイテンシ。hook は Bash 呼び出しのたびに走る)を通していない
現状では判断材料が足りないこと。**再評価の契機**は、`block-dangerous-commands.sh` の
誤検知(上記 FP 2 のような glob 判定)が実作業を繰り返し止めるようになったとき。

**採らなかった候補: FS レベルのロック** (`chflags uchg` / ACL) は全プロセスに
効く真の境界だが、**保護対象が存在しないプロジェクトでは事前にロックできず**、
ロックのために全 repo に `.codex/` を作って回るのは保護目的と本末転倒なので却下した。

### sandbox の excludedCommands が「一次防御」を丸ごと外す経路

上表の「一次: sandbox」は、**同じ Bash 呼び出しに excludedCommands マッチが
1 つでも混ざると成立しない**。Claude Code の Bash tool は 1 呼び出しをまるごと
sandbox 内か外のどちらかで実行する all-or-nothing 設計で、マッチ判定は
**パース済み sub-command 単位・順序非依存**に行われるため(issue #267)。

実測(2026-08-04 / Claude Code 2.1.212 / macOS Seatbelt。`~/` は allowWrite 外):

| 行 | 結果 |
|---|---|
| `touch ~/x.tmp` | `Operation not permitted`(sandbox **内**) |
| `brew --version > /dev/null && touch ~/x.tmp` | 成功(sandbox **外**) |
| `touch ~/x.tmp; gh --version` | 成功(sandbox **外**。除外コマンドは後ろでもよい) |
| `touch ~/x.tmp` / 改行 / `gh --version` | 成功(sandbox **外**。改行区切りでも同じ) |
| `ls ~/.ssh; command gh --version` | denyRead を突破(上流は wrapper コマンドを剥がして照合する) |
| `ls ~/.ssh; g"h" --version` | denyRead を突破(上流はコマンド語のクォートを外して照合する) |
| `ls ~/.aws; FOO='a b' gh --version` | denyRead を突破(クォート付きの代入を前置しても外れる) |
| `ls ~/.aws; FOO+=x gh --version` | denyRead を突破(append 代入でも外れる) |
| `ls ~/.aws; command -p gh --version` | denyRead を突破(wrapper のオプション形でも外れる) |
| `ls ~/.aws; echo ">"& gh --version` | denyRead を突破(クォート内の `>` は複製子ではない) |
| `ls ~/.aws;<TAB>gh --version` | denyRead を突破(区切りの後がタブでも外れる) |
| `ls >""&gh --version` | denyRead を突破(`>` とクォートを挟んでも `&` は区切り) |
| `echo "... gh --version ..."; touch ~/x.tmp` | `Operation not permitted`(文字列言及は非マッチ) |
| `x=$(brew --version); ls ~/.ssh` | `Operation not permitted`(コマンド置換だけでは外れない) |
| `ls ~/.aws; (gh --version)` / `ls ~/.aws; if true; then gh --version; fi` | `Operation not permitted`(subshell / if にも降下しない) |

`~/.ssh` `~/.aws` を使う行は `denyRead` で測っている(sandbox 内なら `ls` が非 0)。
`x=$(brew ...)` の行以外は #267 のレビュー中に code-reviewer が同日 live 実測した。

外れるのは filesystem の `denyRead` / `denyWrite` / `allowWrite` だけでなく、
`network.allowedDomains` と `credentials.files` / `credentials.envVars` の deny も
まとめて(sandbox 化されないコマンドにはどの層も適用されないため。ただし直接
測っているのは上表の filesystem 経路のみ)。**これは Claude Code の仕様**で、
除外を「単独コマンドのときだけ」に絞る指定方法は上流に存在しない
(2.1.220 時点、2.1.212 から変化なし。2026-08-04 実測 — `excludedCommands` の
schema は `array(string)` のままで、粒度を指定するフィールドが無い)。
上流ドキュメントは逆に `docker` / `gh` について excludedCommands の使用を
推奨しており、compound 行での粒度には言及がない。

上流の判定は tree-sitter の `program` / `list` / `pipeline` /
`redirected_statement` を降下して sub-command に割り、wrapper コマンド
(`command` / `builtin` / `noglob` / `nohup` / `nice` / `time` / `stdbuf` /
`timeout`。`-p` / `--` などのオプション形も含む)と環境変数代入(クォート付きの
値・`+=`・配列添字を含む)を剥がし、コマンド語のクォートとバックスラッシュを
外してから prefix 一致を取る(2.1.212 バイナリの `strings` より)。
**コマンド置換 `$(...)` / subshell `(...)` / `if ... fi` には降下しない**
(上表の `x=$(brew --version); ls ~/.ssh` の行と `(gh --version)` / `if` の行が実測)。

| 層 | 実装 | 効くもの | 効かないもの |
|---|---|---|---|
| 二次: hook (Bash) | `claude/hooks/guard-sandbox-exclusions.sh`(Claude 専用の実体。codex には excludedCommands 相当が無いため symlink しない) | compound な行(`;` `\|` `&` 改行で 2 つ以上に割れる行)に除外コマンド名が**単語として現れたら位置を問わずブロック**し、単独実行を強制する | 除外コマンドの**単独行**そのもの。語一致に失敗する形(`(gh` / `x=$(brew` のように区切り文字以外が直前に付くと 1 語になる) |

語一致に失敗する形が今のところ escape になっていないのは、**上流もそこに降下しない
から**であって、hook がそれを判定しているからではない。両者は別の理由で一致している
だけなので、上流が降下し始めると hook 側は無防備になる(下記の「allow 側の前提」参照)。

**判定を「上流の正規化を写す」方式から粗い fail-closed に切り替えた経緯**:
当初はコマンド位置を判定していたが、レビュー 2 周で毎回「写し漏れ」が見つかり、
そのたびに実際に sandbox が外れた(上表の wrapper / クォート分割 / クォート付き
代入 / `+=` 各行)。非公開パーサとの追随になっており、精度を上げるほど写し漏れの
発見が遅れて危険になる。コマンド位置の判定をやめると**その系統の**写し漏れは
無くなる代わりに、`echo "gh のこと"; ls` のように**言及しているだけの行**も止まる。
この誤ブロックは書き方を変えれば解消でき、見逃しとは非対称なので許容する。

**「写し漏れの余地が消えた」とは書かないこと**。語境界判定とクォート走査は
依然としてシェルのトークナイザの近似で、余地はそちらに移っただけ。実際、
方式を切り替えた直後のレビューでも 2 件見つかっている(上表のタブ字下げと
`ls >""&gh`。どちらも live 実測で sandbox が外れた)。

**この hook の退役条件**: 上流に「excludedCommands を単独コマンドのときだけ
適用するオプション」が入れば、hook ごと不要になる。要望を出すのが筋なので、
Claude Code のリリースノートでこの種のオプションを見かけたら §10 のこの節ごと
畳むこと。

**根治の候補として `gh` を sandbox 内で動かす道は、2026-08-04 時点では塞がって
いる**。Keychain 依存は `GH_TOKEN` で外せる見込みだが、TLS 側は外せなかった —
`SSL_CERT_FILE=/etc/ssl/cert.pem` を与えても `tls: failed to verify certificate:
x509: OSStatus -26276` のまま(実測)。Go は macOS では Security framework を使い、
`SSL_CERT_FILE` を見ないため。**この経路を再提案する前に、まずこの実測を
やり直すこと**(Go / gh の更新で変わりうる)。

**ハードニングはここで打ち切る**。探索空間は「非公開・可変」(上流の正規化)から
「公知・有界」(POSIX シェルの字句規則)に縮んだが、後者も完全には尽くせない。
以後 bypass が見つかったら **regression ケースを 1 件足して塞ぐだけ**にし、
判定方式の再設計はしないこと。この hook が防いでいるのは「エージェントが習慣で
`gh ... | jq` と書く」という**偶発的な混在**であって、敵対的な回避ではない —
敵対モデルでは単独行の `brew install` / `gh extension` が最初から素通りするので、
難読化を追いかけても得るものが無い。

**allow 側の前提は block 側より危険な腐り方をする**。block 側の写し漏れは
「hook が止めてくれない」形で live に痛みが出るが、allow 側の前提
(コマンド置換 `$(...)` / subshell に上流が降下しない = 単独扱いでよい) は
**上流の更新で黙って false になり、その瞬間この docs が安全と書いている形が
そのまま escape になる**。`tests/hooks/guard-sandbox-exclusions.cases.jsonl` の
`allow-command-substitution-in-compound` / `allow-subshell-in-compound` が
この前提を pin しているが、pin が見ているのは「hook がその判断を変えていないこと」
だけで、**上流が降下し始めたかどうかは測っていない**(測れない)。
**Claude Code を更新したら、上表の実測を取り直すこと**
(§10 末尾の再確認チェックリスト参照)。

クォート解釈とコメント除去は残してある — `gh ... --jq '.[] | .name'` は
クォート内に区切りを持つ単独コマンドで、既存 skill の主要な使い方だから。
シェルコメント内の言及も落とす(コメントは実行されないので上流も sub-command
として数えない)。落とさないと eval / docs の複数行ブロックが軒並みブロック
され、代償が過大になる。

**これは境界ではなく lint**。hook はコマンド文字列を自前で解釈するので、上流の
パーサと完全に一致する保証はなく、想定外の書き方ですり抜ける余地は残る。
OS が強制する sandbox 本体の代わりにはならない — 「回避不能な層が 1 つ増えた」
とは読まないこと。

残余リスクも「単独行なら安全」ではない。単独行でも `docker run -v /:/host ...` /
`brew install <formula>`(formula の Ruby が host 側で走る)/ `gh extension` は
**sandbox 外での任意コード実行**になる。

hook が入ったことで、`gh` を使う手順は次の形が書けなくなる。skill / eval / docs の
` ```bash ` ブロックを書くときはこれを避けること(ブロックは 1 回の Bash 呼び出しと
みなされるので、**ブロック単位**で見る):

- `gh ... | jq ...` / `gh ... && other` / 他のコマンドと同じブロックに並べる —
  混在なのでブロックされる。`gh` 内蔵の `--jq` を使うか、出力をファイルに落として
  次の呼び出しで処理する
- `cat body.md | gh ...` — 標準入力を pipe で渡す形。`--body-file` / `-F <file>`
  のような中間ファイル経由のオプションに書き換える
- `x=$(gh ...)` — ブロックはされないが、コマンド置換には上流が降下しないので
  **sandbox 内で走り `gh` 自体が失敗する**(実測: `tls: failed to verify
  certificate: x509: OSStatus -26276`)。単独で実行して結果を読み、値はリテラルで
  渡す。**変数は Bash 呼び出しをまたいで保持されない**ので、そもそも
  `before_head=$(...)` 型の記録は次の呼び出しから参照できない — ファイルに
  落とすか、値をリテラルで控える

コード中の文字列としての言及(`echo "gh ..."`)も止まる。**日常の調査コマンドが
これを踏む** — `grep -n 'gh ' <file> | head` のように除外コマンド名を検索語として
渡し、かつ pipe を繋いだ形はブロックされる。pipe を外して 1 コマンドで実行するか、
言及をシェルコメントに移せば通る。シェルコメント(`# gh ...`)は止まらない
(例外: バックスラッシュ行継続の**直後の行**に置いたコメントは止まる。シェルは
コメントとして扱うが hook は語の途中とみなすため — fail-closed 側の誤差)。

バックスラッシュ行継続(`gh api ... \` + 改行 + 続き)は**区切りとして数えない**ので、
複数行に折り返した単独の `gh` 呼び出しは通る。

**除外コマンドを間接的に呼ぶ形は、hook も上流も素通りする**。`make install`
(内部で `brew` を呼ぶ)、`bash seed-sandbox.sh`(中身が `gh`)のように
**コマンド行に除外コマンド名が現れない**起動は、hook がブロックしない代わりに
上流の excludedCommands にもマッチせず、**sandbox 内で走って中の `brew` / `gh` が
失敗する**。手順を書くときは「その script / target が sandbox 内で動くか」を
別途確かめること。動かないものは user が sandbox 外で手動実行する前提にする。

**除外リストを縮める方向は採っていない**。`gh *` は sandbox 内から macOS
Keychain が届かず(実測: `gh auth status` が `The token in keyring is invalid`)、
TLS 検証も通らない(実測: 上記 OSStatus -26276)ため外せない。外すと `/pr`
`/dev` `/next` `dependabot-bulk` が全滅する。`brew *` は sandbox 内でも動く見込みがあるが
`brew install` は未実測。`docker *` / `pnpm test:e2e *` はこの repo では未使用だが、
`claude/settings.json` は**全プロジェクト共通のユーザ設定**なので、この repo での
未使用は削除根拠にならない。

- regression は `tests/hooks/guard-sandbox-exclusions.cases.jsonl` が pin する。
  block 側は上表の「sandbox が実際に外れた行」そのものと、粗い判定の代償
  (コード中の文字列言及)。allow 側は既存 skill が使う bare な呼び方、
  シェルコメント内の言及、旧実装が hang していた形
- 上記の hook テストは**隔離 HOME で走る**ため hook 内の組み込み既定リストしか
  通らない。`excludedCommands` に項目が増えても、また PreToolUse から hook を
  外しても、hook テストは green のまま(vacuous pass)になる。この 2 点は
  `tests/integrity/verify-sandbox-exclusion-guard.sh` が assert する

### herdr socket API と各防御層の関係 — 実測結果

herdr(エージェント用ターミナル multiplexer)の socket API は**認証が無い**。
公式 docs 自身が「socket にアクセスできることは、そのセッション内の shell
アクセスと同等」としている。懸念は `herdr pane run <id> "<cmd>"` が
**Bash tool の sandbox の外にある別プロセスのペインで実行される**点で、
`permissions.deny` と guard hook が**内側のコマンド**に当たるかが問題になる
(#276)。

ここで測っているのは herdr そのものではなく、**§10 冒頭の防御層の表
(一次: sandbox / 二次: hook)が wrapper コマンド越しでも成立するか**なので、
被験体を herdr にした §10 の実測として記録する。

実測(2026-08-07 / Claude Code の Bash tool 内 / sandbox 有効・
`allowUnsandboxedCommands: false` / **herdr ペインの外**で起動したセッション。
`HERDR_ENV` と `HERDR_SOCKET_PATH` がいずれも未設定であることで確認):

| 測ったこと | 結果 |
|---|---|
| `herdr status` | `Error: Os { code: 1, kind: PermissionDenied, message: "Operation not permitted" }` |
| python3 で `~/.config/herdr/herdr.sock`(実在・`srw-------`)に AF_UNIX connect | `PermissionError [Errno 1] Operation not permitted` |
| **対照**: `$TMPDIR` 配下に自分で AF_UNIX socket を bind | `[Errno 1] Operation not permitted`(**herdr 固有の遮断ではなく sandbox の一般制限**) |
| `agents/hooks/block-dangerous-commands.sh` に `herdr pane run 1 "rm -rf ~"` を stdin で与える | **exit=2(ブロック)**「rm -rf で危険なパスが指定されています」 |
| **既知陽性の対照**: 同 hook に `rm -rf ~` を与える | exit=2(ブロック)。検出器が生きていることを確認した上で上の行を測っている |
| `permissions.deny` の 11 パターン | いずれも先頭一致なので `herdr pane run 1 "..."` には**当たらない**(内側は hook が拾う) |
| `sandbox.excludedCommands` | [上節](#sandbox-の-excludedcommands-が一次防御を丸ごと外す経路)の一覧に **herdr は入っていない** → 一次防御が効いている。逆にここへ足すと同節の経路で外れる |

読み取れること:

- **skill を入れるかどうかより前に、Bash tool から herdr を操作すること自体が
  成立していない**。AF_UNIX が sandbox に遮断されるため、`herdr --skill` の
  SKILL.md が前提とする `pane split` → `pane run` → `pane read` の系列は
  ペイン外の Claude Code からは動かない
- **`permissions.deny` が wrapper の内側に当たらないという懸念は当たっていた**が、
  `block-dangerous-commands.sh` は先頭トークンではなく**コマンド文字列全体**を
  走査するので wrapper 越しでも内側の危険コマンドを拾う。deny の穴を hook が
  補完している形
- したがって **`permissions.deny` に `herdr *` 系のパターンは足さない**。先頭一致で
  内側コマンドを網羅することは構造的に不可能で、足すと「塞いだ」という偽の
  安心感だけが残る
- **skill を入れないことは境界ではない**。ペイン内の Claude Code には
  `HERDR_ENV` / `HERDR_SOCKET_PATH` が入るので、指示書が無いだけで
  `herdr` コマンドを叩く能力は残る。境界を担っているのは
  sandbox(一次)と `block-dangerous-commands.sh`(二次)の 2 層であって、
  skill ファイルの有無ではない

**§5 の審査**(この実測を踏まえた `herdr --skill` の採否。結論は
§9「導入を見送った機構」の herdr agent skill 行):

- **出所**: 導入済みの herdr 本体と同一(`herdr --skill` が自分で吐く
  SKILL.md)。本体を入れた時点の出所確認がそのまま使える
- **中身の監査**: 195 行の Markdown なので全文監査できる量ではある。ただし
  上の実測どおり**動かない機能**なので、監査コストを払う理由が無い
- **最小権限**: skill が渡すのは `pane run <id> "<任意コマンド>"` という
  **sandbox 外のプロセスへ任意コマンドを渡す経路**そのもので、能力として過大。
  仮に sandbox の遮断が外れた場合、この skill があると経路が使いやすくなる
  分だけ悪化する
- **lethal trifecta**(秘密データ + 信頼できないコンテンツ + 外部送信):
  外部送信の辺は skill 自体には無い(socket はローカル)が、
  `herdr agent start --kind codex` で**別のエージェントを起動できる**ため、
  起動先のエージェントが持つ経路が実質的に加算される。この評価は
  遮断が外れたときに改めて要る

**sandbox 外の対照**(2026-08-07 / user 実機 / 通常の fish シェル。agent は
`allowUnsandboxedCommands: false` なので測れず、user に依頼して実行した):

`herdr status` は正常に応答し、client / server とも 0.8.0・protocol 19・
`status: running` を返した。**client が使った socket は
`/Users/nakiym/.config/herdr/herdr.sock`** で、sandbox 内で EPERM になったのと
同一パス。よって socket 側の permission や herdr の状態ではなく、
**sandbox が遮断している**ことが対照で確定した。

**未確認**(この 1 点は測っていない。「同じはず」とは書かない):

- **herdr ペインの中で走る Claude Code でも同じ結果になるか** — 上記の計測は
  すべてペイン外から。ペイン内では `HERDR_ENV` / `HERDR_SOCKET_PATH` が入るが、
  sandbox の遮断が同じように効くかは測っていない。**判定は
  `HERDR_SOCKET_PATH` が非空であることを先に確認してから行う** — 空のシェルは
  ペイン外なので、そこで `herdr status` が通っても上の対照の再測にしかならない

**2026-08-06 の計測との差異**: 前日の計測では「`$TMPDIR` への bind は通り、
connect が EPERM」と記録していたが、2026-08-07 は **bind の段階で** EPERM に
なった。「AF_UNIX 操作が sandbox 内で成立しない」という結論は両日で一致するが、
どの system call で落ちるかは一致していない。sandbox プロファイルが変わりうる
ことの実例として残す(§9 の再評価条件が空文でない根拠でもある)。

### 更新チャンネル — `claude-code` ではなく `claude-code@latest` cask を使う

Homebrew は Claude Code の cask を 2 つ出しており、**名前がチャンネルを決める**
(公式 docs を 2026-08-08 に取得して確認。これは docs の読解であって測定ではない):
`claude-code` は stable チャンネルで「約 1 週遅れ、大きな退行を含む版をスキップ
する」、`claude-code@latest` は latest チャンネルで「出た端から受け取る」。両者は
`conflicts_with` なので共存せず、乗り換えは **uninstall → install の順**が要る
(cask 定義と `conflicts_with` は 2026-08-08 に実測)。

**stable を選んでいたのは判断ではなく既定だった**。2026-08-08 に実測した時点で
手元は 2.1.220、upstream は 2.1.226。間の 6 版には許可チェック迂回の修正が
複数入っている(件数を書かないのは、どこまでを「迂回」に数えるかで変わるため。
2.1.222 の PreToolUse auto-allow 迂回、2.1.223 の crafted command / 不可視
Unicode / `bypassPermissions` の 3 件などがある)。うち 2.1.221 の
"Fixed a Bash tool permission-check bypass where zsh could execute hidden
commands in `[[ ]]` regex conditionals" は、**この repo の Bash tool 実行経路
(zsh) に直撃する**。この repo の host 側防御は deny ルールと PreToolUse hook に
乗っているので、その 2 層をすり抜ける穴を 1 週遅れで受け取る設計になっていた。
latest へ移して即日適用する側に倒した(issue #296)。**代償は退行の screening を
失うこと** — 退行を踏んだらこの節に追記してチャンネルを見直す。

**stable へ戻すときは下限を先に下げること**。managed 設定を配置した状態で
stable 側がまだ下限未満の期間(2026-08-08 時点の stable は 2.1.220)に無印 cask へ
戻すと**起動しなくなる**(起動不能の条件そのものは下の
「managed settings で実際に enforce する」節が正本)。

**このシナリオでの復旧は `sudo rm` だけ**。同節がもう 1 つ挙げている
`brew upgrade` は効かない — 無印 cask へ戻した後なので `@latest` は uninstall 済みで
upgrade の対象が無く、`brew upgrade claude-code` も stable が下限未満である限り
上がらない(それがこのロックアウトの定義そのもの)。cask を戻す形で直すなら
upgrade ではなく uninstall → install で `@latest` に入れ直すことになる。

`autoUpdatesChannel` 設定は**書かない**。docs verbatim で
"Homebrew installations choose a channel by cask name instead of this setting"
であり、Homebrew 管理下では読まれない。**チャンネルの正本は Brewfile の cask 名**。

更新の実行経路は `make update` の素の `brew upgrade`。**どちらの cask も
`auto_updates` を設定していない**ため(2026-08-08 に cask 定義を実測)、
`--greedy` は要らない。

### cross-session messaging — 受信を拒否する

2.1.224 で `SendMessage` がセッション間に広がった(CHANGELOG verbatim:
"Claude Code sessions can now message each other, on any of your machines")。
2.1.225 では、**Remote Control セッション相手に限って**それまで相手から届いた後に
返信することしかできなかったのが、こちらから**名前で指定して会話を開始できる**ように
なった(同 verbatim: "SendMessage can now start a conversation with your
Remote Control sessions on other machines by name ... instead of only replying
after they message you first")。**設定ファイルではなく実行中のセッションに届く
入力経路**で、この §10 が 1 つずつ潰してきた経路の一覧に無い種類。この環境では
使う予定が無いので `claude/settings.json` に `crossSessionInbound: "refuse"` を置いた。

**user scope の値が読まれることは確認した**(「効く」= 受信を落とす、ではない。
下記)。#245 の罠(user scope に書いた値が
一度も参照されない)と同型でないかを先に見る必要があるため。2.1.226 のバイナリの
文字列を見ると、このキーには **3 つの出所を書き分けたメッセージが別々に存在する** —
`Your "crossSessionInbound" setting is "hold".` / `Your organization's managed
settings set "crossSessionInbound" to "hold".` / `This repository's settings set
"crossSessionInbound" to "hold" (your own "accept" cannot override a repo
tightening).`。user 自身の設定が読まれ、repo 側は**締める方向にしか**上書き
できない。値は docs によれば `accept`(配信)/ `hold`(通知のみ)/ `refuse`(破棄)で、
`refuse` は破棄に当たる最も厳しい側なので repo 設定から緩められない。

**ただし「refuse が実際に受信を落とす」ことは観測していない**(送る側のセッションを
用意していない)。`claude doctor` が settings の validation error を出さないことと、
上の scope の書き分けまでが実測範囲。#245 の「設定値の存在を防御の根拠にしない」に
従い、ここから先は根拠に使わない。

なお `claude/settings.json` は user scope の実体で、**agent の Edit tool から
書き換えられる**(sandbox の denyWrite は Bash 経路にしか効かない — #212)。
`refuse` を agent が緩められない位置に置きたいなら managed 正本へ移す必要があるが、
現状は入れていない。

**版との関係**は「下限は Claude Desktop が pin している CLI を超えられない」節に
書いた(下限を 2.1.222 へ下げた影響。この節の実測を更新するときはあちらも見る)。

### requiredMinimumVersion — user 設定に書いても enforce されない

**まずこれを読むこと**: `requiredMinimumVersion` は **managed (policy) 設定
からしか enforce されない**。`~/.claude/settings.json`(user scope)に書いた
値は**一度も参照されない**。

**根拠(2026-08-04 実測、`claude` 2.1.220 のバイナリより)**:

- schema の describe に明記 — "Minimum Claude Code version required to start.
  If the running version is older, Claude Code exits at startup with
  instructions to update. **Only enforced from managed (policy) settings.**"
- 判定関数の呼び出し口は 2 つある(通常経路と fast path)が、**どちらも
  `Hr("policySettings")` しか読まない**。user settings を読む経路は
  バイナリ内に存在しない

**つまりこの repo は、この防御層を最初から持っていなかった**。
`claude/settings.json` には長らく `2.1.195` が入っていたが、それは
**起動を止めたことが一度も無い**。issue #245 step 4 が前提していた
「下限を host の実バージョンより上に設定すると Claude Code が起動しなく
なる」は、user scope では成立しない。**「設定してあるから効いている」と
読まないこと** — これは正本ドキュメントが実際に一度間違えた箇所で、
`claude/rules/shell.md` の「確認できないことを検査を緩める根拠に使わない」
と同型の外し方(schema の describe を読めば分かった)。

**それでも値は置いてある**(2026-08-08 時点で `2.1.222`)。enforce されないので
`claude/settings.json` 側の実効は無いが、**下記の managed 設定を導入したときに
そのまま使える正しい値**として置いてある。したがって下限の値は
`claude/settings.json`(宣言・無効)と `claude/managed-settings.json`
(実効・下記の手順で配置したときのみ)の **2 箇所にある。上げるときは両方**
— 実際に効くのは managed 側なので、片方だけ更新すると「settings.json に
書いてある値」と「強制されている値」が食い違う。「依存する挙動がある最小の版」
(strictAllowlist の 2.1.219、symlink 系修正の 2.1.217)ではなく
**この machine で起動する CLI のうち最も古いもの**に合わせている。基準を
「host の実バージョン」から言い直したのは下の節の事故を踏んだため。

### 下限は Claude Desktop が pin している CLI を超えられない

**Claude Desktop はターミナルの `claude` を使わない**。自前の CLI を
`~/Library/Application Support/Claude/claude-code/<version>/claude.app` に
展開して起動し、その `<version>` は **desktop アプリのビルド時に pin されている**
(`app.asar` 内の `buildPinVersion`。`userData/claude-code` 配下へ preseed する
実装)。Homebrew の cask とは別系統なので、`brew upgrade` でも `claude update`
でも上がらない — 上げる手段は desktop アプリ自体の更新だけ。

**2026-08-08 の事故**: managed 設定の下限を `2.1.226`(= ターミナルの
`claude --version`)に上げたところ、desktop アプリが起動のたびに落ちるように
なった。`Claude Code process exited with code 1. stderr: Claude Code 2.1.222 is
older than the minimum version required by your organization (2.1.226).`

このとき desktop アプリ本体は 1.26832.0(自己更新済みで、`brew list --cask` の
記録 1.18286.0 は古い)。**latest チャンネルの cask に合わせた下限は、desktop の
pin より先に進む**。下限を決めるときに見るのは `claude --version` ではなく、
**この machine で起動する CLI 全部のうち最小のもの**。

desktop 側の版を実測する(下限を上げる前にこれを見る):

```sh
ls ~/Library/Application\ Support/Claude/claude-code/
"$HOME/Library/Application Support/Claude/claude-code/<version>/claude.app/Contents/MacOS/claude" --version
```

ディレクトリ名がそのまま pin されている版で、2 行目はそれを直接叩いて裏を取る
形(2026-08-08 はどちらも `2.1.222`)。

**下げても cross-session 受信は復活しない**(上の節の判断を保つ根拠)。
2.1.222 のバイナリに `crossSessionInbound` は **0 件**、比較のため同じ
バイナリで `requiredMinimumVersion` は 5 件ヒットする(`strings` は効いている)。
2.1.224 で入った受信経路が 2.1.222 には無い。ただし下限が 2.1.222 になると
**2.1.224 / 2.1.225 も許可される** — この machine には入っていないが、下限は
その 2 版を止めない。

下限を下げる代わりに desktop へ新しい CLI を使わせる案(`app.asar` の
`CLAUDE_CODE_LOCAL_BINARY` override)は、GUI アプリへの env 注入が要るうえ
pin と違う版を desktop⇄CLI 間で使うことになるため採らなかった。**未検証**。

### managed settings で実際に enforce する(user 操作)

enforce したいなら managed (policy) 設定に置く。この repo は正本を
`claude/managed-settings.json` に持つが、**symlink では配線しない**
(`scripts/link.sh` の対象外)。理由は 2 つ:

- managed 設定は**この repo の設定群のうち唯一 admin 所有であるべきもの**。
  user 書き込み可能な repo への symlink にすると、**agent が Edit tool で
  policy を書き換えられる**(`~/.claude/settings.json` が実際にそうなって
  いるとおり、Edit 経路には sandbox の denyWrite が効かない —
  memory `project_settings_files_sandbox_lock`)。policy を repo に
  symlink するのは権限昇格の経路を自分で作ること
- macOS の配置先 `/Library/Application Support/ClaudeCode/` は agent から
  書けない。**塞いでいるのは OS の権限**(`root:admin` の `drwxr-xr-x` で
  group に write bit が無い)であって sandbox ではない — sandbox の
  filesystem 制約は Bash 経路にしか効かないので、Edit tool 経路まで
  含めて言うなら根拠は OS 権限のほう。**層を取り違えないこと**
  (この節が直したのと同型の外し方)

導入する場合は user が手で行う(要 admin パスワード)。**内容の確認は
repo 側のファイルではなく、root 所有にコピーした後の実体に対して行う** —
`claude/managed-settings.json` は working tree の通常ファイルなので agent が
Edit tool で書き換えられ、**「確認 → cp」の順だと確認した内容とコピーされる
内容が別になりうる**(確認とコピーの間に書き換えられる)。managed 設定は
permissions / sandbox を含む全設定を最優先で上書きできるので、改変されたまま
昇格させると影響は下限値だけでは済まない。

配置先ディレクトリは `root:admin` の `drwxr-xr-x` で **user には write bit が
無い**。したがって一度 `sudo cp` でそこへ置いたファイルは agent には触れない。
これを使って「書き換え不能にしてから確認し、確認したものをそのまま昇格する」
順にする:

```sh
sudo mkdir -p "/Library/Application Support/ClaudeCode"
sudo cp claude/managed-settings.json "/Library/Application Support/ClaudeCode/managed-settings.json.staged"
sudo cat "/Library/Application Support/ClaudeCode/managed-settings.json.staged"
sudo mv "/Library/Application Support/ClaudeCode/managed-settings.json.staged" "/Library/Application Support/ClaudeCode/managed-settings.json"
```

3 行目で目視し、内容が意図どおりのときだけ 4 行目を実行する。`mv` は同一
ファイルシステム内の rename なので atomic で、**確認した実体がそのまま
managed-settings.json になる**。意図しない内容だったら
`sudo rm "/Library/Application Support/ClaudeCode/managed-settings.json.staged"`
で捨てる(この時点ではまだ policy として読まれていない)。

**入れる前に必ず確認すること**: managed 設定の下限を満たさない CLI では
Claude Code が**起動しなくなる**。`claude --version` が下限以上であることを
全マシンで確かめ、**加えて Claude Desktop が pin している CLI のバージョンも
別途確かめる**(上の節。`claude --version` だけ見ると desktop を落とす)。
ロックアウトからの復旧経路は 2 つ:

- `update` / `install` / `doctor` の 3 サブコマンドだけは下限チェックの例外
  として通る。ただし **Homebrew cask 管理下ではこの `claude update` は自己更新
  せず案内を出すだけ**なので、実際に叩くのは `brew upgrade claude-code@latest`
  (これは `claude` を経由しないので下限に関係なく通る)
- 直接のロールバックは
  `sudo rm "/Library/Application Support/ClaudeCode/managed-settings.json"`
**前提**: user は全マシンで常に最新を使う運用(2026-08-04 に本人確認)。
`scripts/link.ps1` が配線する Windows 側にも同じ判断が要る(配置先は
Windows の managed settings パスで、上のコマンドはそのままでは使えない)。

### managed 設定は原則触らない — 判断基準は「復旧に sudo が要るか」

**このファイルは触るたびに起動不能を引いている**。#302 は下限を上げて Claude
Desktop を落とし(§10「[下限は Claude Desktop が pin している CLI を超えられない](#下限は-claude-desktop-が-pin-している-cli-を超えられない)」)、
#297 は `disableSideloadFlags` を入れて Claude Code の起動経路を落とした(下の節)。
2 サイクル連続で、いずれも「設定値は仕様どおり正しい」まま壊れている。

原因は個別の値ではなく**着手判断**にある。managed 設定の本来の価値は「組織の
管理者が、開発者に policy を外させない」ことだが、**この repo は user と管理者が
同一人物**なので、その価値の大半は守る相手がいない。残る利点は「agent が自分の
権限を広げる経路を塞ぐ」だけで、対価は**失敗すると起動不能になりうること、
そしてその復旧に admin パスワードが要ること**(起動をゲートするキーに触った
場合。下の `sandbox.credentials` のように壊れても起動する種類は別枠)。この非対称を天秤に載せず、外部サーベイ由来の推奨を
「正しいか」だけ検証して入れたのが両方の入口だった。

**着手基準の正本は [`claude/rules/managed-settings.md`](../claude/rules/managed-settings.md)**
(`claude/managed-settings.json` を触ったときだけ lazy load される)。ここに複製せず、
基準を変えるときはそちらを直す。この節は事故の経緯と、なぜその基準になったかを残す。

### disableSideloadFlags — 実測して見送った(#297)

`--plugin-dir` / `--plugin-url` / `--agents` / `--mcp-config` を起動時に拒否する
managed 専用キー(2.1.193 以降)。**2026-08-09 に実配置して実測し、見送った。**

docs は影響範囲を「currently Cowork local sessions in the desktop app」と書いて
いたが、**実際にはそれより広い**。Cowork を使っていない状態でも、`--plugin-dir`
を内部で渡す経路が別にあり、Claude Code のプロセスが exit code 1 で落ちた:

```
Claude Code process exited with code 1. stderr: --plugin-dir is disabled by your
organization's managed settings (disableSideloadFlags).
```

**フラグを落として続行する形ではなく、プロセスごと落ちる。** エラーが設定名を
名指しするので原因の特定自体は即座にできた。

得られるものも当初の見積もりより狭かった(内訳と再評価条件は §9 の行)。

### sandbox.credentials の deny を managed 側に 1 件置く理由(#297)

`claude/managed-settings.json` の `sandbox.credentials.files` に `~/.ssh` の
`"mode": "deny"` を 1 件置いている。**この 1 件の目的は認証情報の保護ではない**
(それは user 設定側の 4 件が既にやっている)。目的は
`sandbox.filesystem.disabled` を **managed 設定からしか設定できないキーに変える**
ことにある。docs 逐語:

> When managed settings configure `sandbox.filesystem` at all, or list any
> `sandbox.credentials.files` entry with `"mode": "deny"`, only managed settings
> can set the key.

`filesystem.disabled` を押せる場所は 3 つに限られる(docs 逐語):

> User settings, managed settings, and the `--settings` CLI flag can set it.
> Project settings in `.claude/settings.json` and `.claude/settings.local.json`
> can't, so a checked-out project can't switch filesystem isolation off.

このうち user 設定は agent の Edit tool から書き換えられる
(§10「[managed settings で実際に enforce する](#managed-settings-で実際に-enforce-するuser-操作)」)。
**この経路が閉じることは docs の記述に拠っており、実測はしていない** —
user 設定に直接 `filesystem.disabled` を書いた状態は試していない。
実測できたのは下の `--settings` 経路だけで、**pin の主目的である user 設定経路の
方が未実測**である。

**実測(2026-08-09、Claude Code 2.1.226、managed 配置後)**:
`claude --settings '{"sandbox":{"filesystem":{"disabled":true}}}'` で起動し
`/sandbox` の Config タブを見たところ、Filesystem Read / Write Restrictions が
**表示されたまま**だった(注入した `disabled` が無視された)。
**対照は取っていない** — managed 未配置の状態で同じコマンドが `disabled` を
反映することは確認していないので、「2.1.226 では `--settings` がこのキーに
そもそも効かない」可能性を排除できていない。

**塞がるのは `filesystem.disabled` のキー 1 つだけで、隔離全体ではない。**
引用した仕様が managed 専用にすると言っている "the key" は `filesystem.disabled`
であって、`sandbox.enabled` を pin するとは書かれていない。user 設定の
`"enabled": true` を Edit tool で `false` にする経路が残るかは**実測していない**。
「隔離そのものを外せなくなった」と読まないこと。

配列キーは全 scope でマージされ、どの scope も他が足した deny を外せない
(docs 逐語: 「For array keys such as `excludedCommands` and `allowRead`, Claude
Code merges entries from every scope」)。したがって user 設定側の既存 4 件は
そのまま効き続ける。増えるのは「外せなくなる」ことだけで、**起動をゲートしない**
(下限や `disableSideloadFlags` と違い、壊れても起動はする)。

### network.strictAllowlist — 許可外ホストを確認ダイアログ抜きで拒否する

`sandbox.network.strictAllowlist: true`(issue #245 step 5、Claude Code
2.1.219 以降)。既定では `allowedDomains` に載っていないホストは**確認
ダイアログ**になるが、この repo は確認を減らす方向に倒しているので、
**最後の砦がいちばん出したくないダイアログ**という状態だった。有効化すると
決定的に拒否される。

**適用範囲(2026-08-04 実測、`claude` 2.1.220 のバイナリより)**。判定は
`deniedDomains` → `allowedDomains` の順に走り、どちらにも当たらなかった
ときの既定が「user に聞く」から「拒否」に変わるだけ。つまり
**`allowedDomains` の中身は変えていない** — 締まるのはリスト外の扱い。

| 論点 | 実測 |
|---|---|
| どの設定 scope から効くか | **user / managed(policy)/ CLI (`--settings`) のみ**。project の `.claude/settings.json` `.claude/settings.local.json` からは**無視される**(schema の describe に明記。設定 scope の列挙関数も managed + flag + userSettings の 3 つを返す) |
| symlink 越しでも user scope か | **効く(根拠は実装の読み取り)**。`~/.claude/settings.json` は repo への symlink だが、scope は「どの source slot から読んだか」で決まり実体パスは見ないため。live probe(許可外の `gitlab.com` が `CONNECT tunnel failed, response 403` で即落ち)は**この仮説と整合するが判別力は無い** — 非対話セッションでは strictAllowlist が無くても確認プロンプトが自動 deny されて同じ結果になる。判別まで取るなら対話セッションでプロンプトが出ないことを見る |
| `allowedDomains` 自体の scope | strictAllowlist と違い **project 設定からもマージされる**。この repo の `.claude/settings.json` が足している `formulae.brew.sh` / `ghcr.io` は有効なまま。さらに **`permissions.allow` の `WebFetch(domain:X)` ルールも同じ allowlist にマージされる**(実測: allowlist 構築関数が `permissions.allow` を走査して `domain:` 接頭辞を剥がし `allowedDomains` に push する)。この repo で `www.anthropic.com` に到達できるのはこの経路 — gitignore 済みの `.claude/settings.local.json` の `WebFetch(domain:www.anthropic.com)` が由来で、settings に無い組み込みホストがあるわけではない。**「WebFetch を許可すると sandbox 化された Bash の egress も開く」** という非自明な結合なので、`WebFetch(domain:...)` を足すときは egress を開けてよい相手かで判断する。加えてセッション中に承認したホストも合流するため、許可ホストの集合を設定ファイルの列挙だけで書き下すことはできない |
| WebFetch は締まるか | **締まらない**。schema に "in-process tools such as WebFetch are not gated by this setting" と明記。効くのは **sandbox 化された Bash コマンドだけ** |
| `excludedCommands` は締まるか | **締まらない**。上の「excludedCommands が『一次防御』を丸ごと外す経路」節のとおり、除外コマンド(`gh` / `brew` / `docker` / `pnpm test:e2e`)を含む行は sandbox 外で走るので `allowedDomains` ごと素通りする。**`gh` は任意ホストへ通る** — 「許可外は決定的に拒否」と要約して読むとここが盲点になる |

**運用上の注意**: 拒否は確認ダイアログを出さないので、症状は
「なぜか通信できない」という形でしか現れない。見分けるには
`No matching config rule, denying` の debug ログを見る。これは全プロジェクト
共通のユーザ設定なので、`allowedDomains` を持たない別 repo で作業すると
user 設定の 10 ドメイン外はこの形で落ちる。正当なドメインが必要に
なったら、repo 側の `.claude/settings.json` に足すか user 側に足すかを選ぶ
(前者のほうが影響範囲が狭い)。

**導入直後は能動的に観察する**(issue #245 step 5)。拒否が無言である以上、
「足りないドメインがあること」は待っていても報告されない。有効化から数
セッションは、通信が理由不明で落ちたときに `No matching config rule, denying`
の debug ログを確認する習慣を意識的に持ち、出てきた正当なドメインを
`allowedDomains` に足す。

### codex CLI 自身の config.toml 書き込みと deny の相互作用

**codex CLI は config.toml を動的に書く**。`[projects.*]`(repo の
trust_level 記録)/ `[plugins.*]` / `[notice.*]` / `[tui.*]` /
`[hooks.state]`(hooks.json の trusted_hash 承認)がその対象で、
`scripts/codex-merge-config.sh` はこれらを「dest 側で保護するセクション」として
扱っている。つまり deny 下ではこれらの記録が失敗しうる。

- 発生条件: **未 trust の repo で初回実行**・codex 更新後の notice/tui 記録・
  `codex/hooks.json` 変更後の再承認。日常の codex-review (trust 済み repo・
  hooks.json 不変) では発生しない
- 症状: codex 側の warning、または trust 確認の再表示。sandbox 内の
  codex-review が失敗した場合は `run-review.sh` の exit 3 (SKIP) 経路になる
- 復旧: **ユーザーが sandbox 外で codex を 1 回起動**して記録を書かせる
- `make link` / `make install` を agent が実行した場合、config.toml のマージだけが
  warn でスキップされ他の symlink 処理は継続する(`scripts/link.sh` /
  `link.ps1` で明示的に warn-continue にしている)

### codex の hook 承認 (`trusted_hash`) の適用範囲 — 実測結果

`~/.codex/config.toml` の `[hooks.state."<hooks.json path>:<event>:<group>:<index>"].trusted_hash`
は、**hook の設定 identity だけをハッシュしており、参照先スクリプト本体の内容は
一切含まない**。codex CLI **0.145.0** で実測して確認し(issue #207)、
**0.146.0 で再実測して同じ仕様であることを確認した**(issue #214、2026-08-03)。

根拠は 2 系統:

1. 上流実装(`openai/codex`)。`codex-rs/hooks/src/engine/discovery.rs` の
   `command_hook_hash()` は `{event_name, matcher, hooks: [normalized_handler]}`
   を組み立てて `version_for_toml()` に渡すだけで、`normalized_handler` は
   command 文字列 / timeout / async / statusMessage / additionalContextLimit
   から成る設定値。同関数のドキュメントコメントが目的を明示している —
   *"Hash a normalized, config-derived identity instead of source text so
   equivalent hooks from config TOML and hooks.json converge on the same trust
   identity."*。`version_for_toml()`(`codex-rs/config/src/fingerprint.rs`)は
   その値を canonical JSON(オブジェクト key を再帰ソート)にして sha256 する
2. 再現実測。上記を再実装して、この機体の `~/.codex/config.toml` に記録済みの
   `trusted_hash` を再現した。**0.146.0 では 6 件すべてバイト一致**
   (0.145.0 時点では 5 件で、残る 1 件は Stop event の既定値が未特定だった)。
   再現できた payload の例:

   ```
   {"event_name":"pre_tool_use","hooks":[{"async":false,"command":"bash \"$HOME/.codex/hooks/block-dangerous-commands.sh\"","statusMessage":"コマンド安全性チェック中...","timeout":10,"type":"command"}],"matcher":"^Bash$"}
   → sha256:926d8278e318187e63816360f984fd354cad9dec305d9e7f4154a02377b3f39d
   ```

   payload は次のオブジェクトの canonical JSON(キー再帰ソート・compact・
   UTF-8 生出力・末尾改行なし)で、その sha256 hex が `sha256:<hex>` として
   記録される。**未再現だった 1 件の原因は下 2 つの規則**だった:

   | キー | 内容 |
   |---|---|
   | `event_name` | event 名の snake_case(`PreToolUse` → `pre_tool_use`) |
   | `matcher` | その group の matcher。**空文字列のときはキーごと省略される**(`"matcher":""` ではない) |
   | `hooks` | 要素 1 個の配列。**group 全体ではなくその index の hook だけ**が入る |
   | `hooks[].type` | 既定 `"command"` |
   | `hooks[].command` | `hooks.json` のまま |
   | `hooks[].async` | 既定 `false` |
   | `hooks[].timeout` | **`hooks.json` に無いときの既定は 600** |
   | `hooks[].statusMessage` | `hooks.json` に無いときはキーごと省略 |
   | `hooks[].additionalContextLimit` | 同上。ただし**この 1 つだけ実測の裏が無い** — 上の上流実装読解に従って含めているが、この機体の `codex/hooks.json` はどの hook でも使っておらず、記録済み hash 6 件は「キーが無い」側でしか検証できていない。外れても方向は fail-loud(MISMATCH になるだけで、承認済みと誤報告する側には倒れない) |

   **この表は `tests/integrity/verify-codex-hook-trust.sh` のヘッダと
   `JQ_ENTRIES` が正本で、ここはその写し**(仕様を直すときは必ず先に
   スクリプト側を直す。実際に hash を計算しているのはスクリプトなので、
   食い違ったときに正しいのは常にそちら)。仕様は同スクリプトに実装済みで、
   `make test` / `make gate` のたびに記録値と突き合わせている。**再実測は
   手順書ではなくテストになった** — codex を upgrade して仕様が変われば
   MISMATCH として出る(見逃しではなく fail-loud)。ただし **「仕様変更なら
   全件 MISMATCH」とは限らない**: 既定値や省略規則の変更は*その規則に依存する
   entry だけ*を外す(実測: `timeout` 既定値を変えた mutant はこの機体の
   8 entry 中 1 件しか外さなかった)。MISMATCH を見たら件数で判断せず、
   **その entry の `hooks.json` を変更した覚えがあるか**で切り分け、覚えが
   無ければ**再承認する前に**再実測する(再承認すると codex が新しい hash を
   書き戻し、仕様が変わった証拠が消える)。回帰は
   `tests/integrity/run-integrity-selftest.sh` の
   `trust-hash-*` ケースが固定している(期待 hash は独立した定数として持ち、
   `hooks.json` 側だけを書き換える mutation で導出関係を測る)。

**帰結**: `~/.codex/hooks/*.sh` の中身を差し替えても codex は再承認を求めず、
次回起動時に無警告で host 側で実行する。**codex 側の hook 承認機構は
スクリプト改変に対する backstop にならない**。逆に、`hooks.json` の
command 文字列・matcher・timeout・statusMessage を変えると hash が変わり
再承認が要る(実際 `codex/hooks.json` に hook を追加した直後は、その entry が
Untrusted となり承認するまで実行されない)。

この結論は codex の実装詳細に依存するため、**codex を upgrade したら再実測する**
(本節にバージョンを明記してあるのがその trigger)。ただし再実測の実体は
上記のとおり `make test` が自動で行うので、**upgrade 後にやることは
「`make test` を回して MISMATCH が出ないことを確認する」**に変わった。
MISMATCH が出たら(件数を問わず)、その entry の `hooks.json` を変更した
覚えが無い限り payload 仕様変更を疑い、本節の表と
`verify-codex-hook-trust.sh` のヘッダを実測し直して更新する。

### hooks 系ファイルの防御層

`~/.codex/hooks.json` / `~/.codex/hooks/` / `~/.codex/skills/` は
`scripts/link.sh` が張る **repo への symlink** で、実体は git 追跡下にある。
host 側の実ファイル `~/.codex/config.toml`(これが git 追跡外。repo 側の
`codex/config.toml` は追跡下で、merge 経由で host に反映される)との
非対称性はここにある。したがって
**commit 済みの改変は PR review + `tests/integrity/run-integrity-check.sh`
(symlink 置換の検出)で見える**。残るリスクは「**commit されていない改変**」で、
この repo の cwd は sandbox の allowWrite なので、正当な hook 開発と区別できない。

| 層 | 実装 | 効くもの | 効かないもの |
|---|---|---|---|
| 検知 (session, Claude Code) | `agents/hooks/hooks-integrity-warn.sh` を `claude/settings.json` の SessionStart (`startup\|resume\|clear\|fork`) に配線 | セッション開始時に、監視対象の未コミット改変を警告として context に注入する。**自動で発火する経路**(model の context に入り、人は transcript で確認できる) | 警告のみで遮断はしない(dotfiles 開発中は dirty が正常状態のため意図的に warn-only)。**codex 単体の作業では発火しない**(下の行が担当) |
| 検知 (session, codex) | 同 hook を `codex/hooks.json` の SessionStart (`startup\|resume\|clear`) に配線(issue #215)。`codex/hooks/hooks-integrity-warn.sh` は正本への相対 symlink | **(codex TUI で承認された後に限り)** codex CLI 単体で作業する経路。本節の脅威モデルの中心は codex 側なので、ここが塞がって初めて主要経路が覆われる | 同上(warn-only)。加えて **承認するまで発火しない** — 新 entry は trusted_hash 未登録で Untrusted 扱いになる(承認は host 側の user 操作で、agent からは行えない)。この「配線済みだが未承認」状態自体は下の承認状態検査が拾う |
| 承認状態の検査 | `tests/integrity/verify-codex-hook-trust.sh` を `make test` と `tests/run-gate.sh` から呼ぶ(issue #239 でキー存在、issue #214 で `trusted_hash` の値検証) | `codex/hooks.json` の各 entry に対応する `[hooks.state."<hooks.json の絶対パス>:<event>:<group>:<index>"]` キーが `~/.codex/config.toml` に無い状態 = **配線済みだが未承認(一度も実行されない)** の検出。新しいマシンにセットアップして承認を忘れた場合も同じ形で出る。監視系 hook は「警告が出ない = 正常」と「そもそも動いていない」が区別できないため、ここを機械が言わないと誰も気付けない。加えて記録済み `trusted_hash` を現在の `hooks.json` から計算し直して突き合わせるので、**「承認後に command を書き換えた」= その entry が Untrusted に戻って実行されていない**状態も拾う(キー存在だけを見ていた頃はこれを「承認済み」と誤報告していた) | 承認も再承認も user 操作でしか行えないので**警告のみ**(全経路 exit 0。agent が直せないものでゲートを落としても手詰まりになる)。値検証は codex の payload 仕様に依存するため、仕様が変わると MISMATCH になる(見逃しではなく fail-loud)。ただし**外れるのは変わった規則に依存する entry だけ**なので、**件数では原因を判別できない** — 「承認後の書き換え」と「仕様変更」の区別は「その entry の `hooks.json` を変更した覚えがあるか」で行い、覚えが無ければ**再承認する前に**再実測する(再承認は仕様変更の証拠を消す)。`jq` と `sha256sum`/`shasum` が無い環境では SKIP。キー書式は codex-cli 0.146.0 で実測(2026-07-31)、payload 仕様も同 0.146.0 で実測(2026-08-03)。**Stop hook 経由では表示されない**のは下の「検知 (手動)」と同じで、人の目に入るのは `make test` / `make gate` を手で叩いたときだけ |
| 検知 (手動) | `hooks-integrity-warn.sh` を `make test` と `tests/run-gate.sh`(`make gate`)からも呼ぶ | **手で `make test` / `make gate` を叩いたとき**の表示 | **Stop hook 経由では表示されない** — `stop-verify-gate.sh` は gate の出力を変数に capture し、gate が通れば捨て、落ちても `tail -20` しか出さないため。ターンごとの自動検知にはなっていない |
| 構造検査 | `tests/integrity/run-integrity-check.sh` | symlink が期待どおりの実体を指しているか(置換・実体化の検出)。ズレは異常なので exit 1 | ファイル**内容**の改変 |
| review | git 追跡 + PR review | push されて PR に載った改変 | 未コミットの改変(検知層が担当)と、**push されないローカル commit**(下記) |

監視対象は「host 側で起動されるコマンドを**直接**定義しているファイル」に限る
(`agents/hooks/` `claude/hooks/` `codex/hooks/` `codex/hooks.json`
`codex/config.toml` `claude/settings.json` `claude/statusline.sh`
`.claude/settings.json` `.claude/stop-gate.conf`)。`.claude/settings.json` は
コマンドを直接は書かないが、**何を承認なしに実行できるか / どこに書けるか**を
決めるので同じ脅威モデルに属する。
`.claude/stop-gate.conf` 経由で間接的に host 実行される `tests/` / `Makefile` /
`scripts/` まで広げると、この repo のほぼ全変更で警告が出て signal が消えるため
含めない。網羅性は `tests/hooks-integrity/run-hooks-integrity-tests.sh` が
配線 (`settings.json` / `hooks.json` の command) から抽出して assert する。

**残余リスク(塞げていないもの)**:

- **codex 側の配線は codex TUI で承認するまで発火しない**(issue #215 で配線自体は
  入れた)。`codex/hooks.json` に entry を追加すると trusted_hash が変わり、その entry は
  Untrusted 扱いで実行されない。承認は **host 側の user 操作**で、agent からは行えない。
  承認前は issue #215 以前と同じ状態 — Claude Code を経由せず codex CLI 単体で作業して
  `codex/hooks/*.sh` を未コミット改変した場合、`make gate` / `make test` を手で回さない
  限り警告は出ない。なお **codex の Stop hook は依然 `notify-stop.sh` を呼ぶだけ**で
  `run-gate.sh` には繋がっていないため、codex 側の自動検知はセッション開始時のみ
  (ターンごとではない)
- **ローカル commit すると検知が消える**。検査は `git status --porcelain`
  (HEAD との差分)なので、改変を commit した時点で clean になる。push されない
  ローカル commit は PR review にも載らないため、「commit されていれば review で
  見える」が成立するのは **push された場合だけ**。この窓を塞ぐ層は現状無い
- **検知層の配線先そのものが監視対象の内側にある**。`claude/settings.json` の
  SessionStart entry を消す編集と hook 本体の改変を同時に行うと、次回起動時には
  新しい settings.json が読まれるため警告は出ない(自己隠蔽)。settings.json は
  監視対象なので **改変した回の警告は出る**が、それを人が見落とせばそこで途切れる
- **無関係なプロジェクトのセッションでも警告が出る**。配線先は
  `~/.claude/settings.json` と `~/.codex/hooks.json`(どちらもグローバル)で、hook は
  cwd を無視して dotfiles repo を見る。dotfiles を dirty のまま別プロジェクトで
  作業している間はずっと同じ警告が context に入り、warn-only の signal が摩耗する。
  codex 側を配線した分、この摩耗は増える方向に働く(issue #215)
- **警告本文には `git status --porcelain` のパス文字列がそのまま載る**。監視対象
  ディレクトリにファイルを置ける主体は、両 harness の context に入るテキストの一部を
  制御できる(ファイル名経由の prompt injection 経路)。実害は低い — その前提能力は
  「repo に書ける = host で任意コード実行できる」(本節末尾)と同値で、より強い経路を
  既に持っている。ただし **codex 側にも毎セッション注入されるようになり、経路が
  harness 2 系統に広がった**(issue #215)。ファイル名を伏せると警告の用をなさないので
  出力自体は変えていない
- **`.gitignore` にマッチする新規ファイルは `-uall` でも見えない**。`.gitignore`
  自体も監視対象外なので、「`.gitignore` に追記 → 無視されるファイル名で設置」の
  2 手で検知を避けられる(それ単体では実行に繋がらないが、fail-open の穴の一つ)
- `block-dangerous-commands.sh` の `_check_glob_seg` は segment 単位で
  「引数の path component が `.codex` にマッチするか」を見るため、
  `cd ~/.codex/hooks && printf ... > block-dangerous-commands.sh` のように
  **書き込み segment 側に `.codex` component が現れない形は素通しする**。
  config.toml は sandbox の denyWrite が backstop になるが、hooks 系には
  backstop が無い。`cd` 追跡を足しても `bash -c` や変数間接参照など回避経路が
  残り、Bash コマンド文字列の静的検査は原理的に迂回可能なので、ここは
  遮断ではなく上表の検知層で受ける設計にしている
- repo 内の `codex/hooks/*.sh` を直接編集する経路は sandbox で allow されている。
  この repo の目的がそれらの編集そのものなので block できない
- **repo の hook 実装は host 側で実行される = 実質 trusted zone** である。
  この repo に書き込める主体は、次回の Claude Code / codex 起動時に host 上で
  任意コードを実行できると考えること

### SessionStart hook の実測結果 — codex / Claude Code 両方(この節が正本)

**再確認の trigger は harness ごとに 2 系統ある。どちらか一方を上げたら、
その側の項目を読み直す**(片方だけ更新して他方が取り残されるのを防ぐため、
各項目の冒頭に測定日と対象 harness を書いてある):

- **codex を upgrade したら** — 1 / 2 / 3、および §10 冒頭の trusted_hash
  (trusted_hash は `make test` が自動で突き合わせるので、**回して MISMATCH が
  出ないことを確認する**だけでよい。出たら件数を問わず仕様変更を疑う)
- **Claude Code を upgrade したら** — 2b / 2c、および
  「sandbox の excludedCommands が『一次防御』を丸ごと外す経路」節の実測表。
  とくに **allow 側の 2 行**(`x=$(brew --version); ls ~/.ssh` と subshell / if の行)
  を測り直すこと — この 2 つは `guard-sandbox-exclusions.sh` が「単独扱いでよい」と
  判断する根拠で、上流が降下するようになると**黙って escape 経路に変わる**。
  block 側の写し漏れと違い、live に痛みが出ないまま前提だけが false になる

**codex 側の記述**(1 / 2 / 3)はすべて **2026-07-31 に upstream の tag
`rust-v0.146.0`(host の codex-cli 0.146.0)のソースを読んで確認**した
(実際に codex を起動して発火させた観測ではない — 本節の配線は執筆時点で
未承認のため)。
hook 本体とテストのコメントはこの節を指すだけに留めてある(同じ実測事実を複数箇所に
書くと、upgrade で挙動が変わったときに片方だけ更新されて食い違うため)。

**Claude Code 側はソースが公開されていないので、根拠の強さが項目ごとに違う**。
matcher の突合方式(下の 2b)は配布バイナリを読んで確認したが、
「Claude Code 側では stdout が素通し」(下の 3)はこの repo での運用上の観測
(SessionStart hook の stdout がそのまま context に入っており、JSON 風かどうかで
落ちた例が無い)にとどまる。どちらも codex 側の記述と根拠の強さが違う点に注意。

**1. matcher は SessionStart でも有効**。突合対象は `SessionStartSource` の
`startup` / `resume` / `clear` / `compact`。matcher が無視される(実装上
`matcher_pattern_for_event` が `None` を返す)のは **`UserPromptSubmit` と `Stop` の
2 イベントだけ**(`codex-rs/hooks/src/events/common.rs`、同 `session_start.rs`)。

**2. matcher の突合方式は 3 通りに分岐する**(同 `common.rs` の `matches_matcher`)。
ここを取り違えるとテストだけが通る(以前この行は「2 通り」と書いていたが、
直下の表は当初から 3 行あった。**再実測して変えたのではなく、本文が表と
食い違っていたのを直しただけ** — 測定日は上記 2026-07-31 のまま):

| matcher | 判定 |
|---|---|
| `""` / `*` | `is_match_all_matcher` → **無条件に match** |
| 英数字 / `_` / `\|` のみ | `is_exact_matcher` → `split('\|')` して**完全一致**(部分一致しない) |
| それ以外 | regex として評価 |

配線している `startup|resume|clear` は 2 番目に当たり **exact 一致**で評価される。
テスト側で bash の `=~`(部分一致)だけを掛けると、`tartup|esume|lear` のような
綴り違いが「一致する」と判定されて通るのに codex では一度も発火しない。よって
`tests/hooks-integrity/run-hooks-integrity-tests.sh` の codex 側 matcher 検査は
**全文 pin** にしてある。

**2b. Claude Code 側も同じ 3 分岐だった**(2026-08-01 実測、`claude` 2.1.212)。
以前この節には「Claude Code の regex 一本槍とは違う」と書いてあり、それを根拠に
ケース 12(Claude 側)だけ部分一致の緩い検査を許していたが、**前提が誤っていた**。
host のバイナリ(`/opt/homebrew/Caskroom/claude-code/2.1.212/claude`)の
matcher 関数は、**SessionStart を含む一部イベントでは** matcher が
`^[a-zA-Z0-9_|, -]+$` に当たると `split(/[|,]/)` して trim したうえで
`.includes(source)` で**完全一致**判定し、regex(`new RegExp(matcher)`)を
使うのはそれ以外の形のときだけ。`""` / `*` が無条件 match なのも同じ。
**「一部イベントでは」を落とさないこと** — 許容文字集合と分割文字は
イベント名によって 2 択に分かれており(SessionStart は広い側)、他のイベントに
この記述をそのまま転用すると外れる。

よって `startup|resume|clear|fork` は **exact 一致**側に落ちる。
**綴り違いを取り逃がす穴という点では codex と同型**(ただし exact 側に入る
*条件*は同じではない — Claude は `,` と `-` も許すので、例えば
`startup, resume` は Claude では exact 側、codex では regex 側に落ちる。
現行の配線はどちらも `|` 区切りのみなので実害は無い)。
ケース 12 も **全文 pin** に直した。

根拠の強さは codex 側と違う点に注意 — codex は upstream のソース、こちらは
**配布バイナリの minify 済みバンドル**から読んだもので、版が上がれば黙って
変わりうる。**Claude Code を upgrade したらここも再確認する**。

**再確認済み(2026-08-04 / `claude` 2.1.220、issue #245 step 2 の更新に伴う)**。
matcher 関数の構造は 2.1.212 から**変わっていない** — `!matcher` / `"*"` を
無条件 match とし、許容文字集合(SessionStart 側は `^[a-zA-Z0-9_|, -]+$`、
狭い側は `^[a-zA-Z0-9_|]+$`)に当たれば `split` → `trim` → `includes` の
**完全一致**、当たらなければ `new RegExp(matcher)` という 3 分岐のまま。
唯一の差は完全一致側・regex 側とも**別名展開を経由するようになった**こと
(tool 名の別表記も突き合わせる)で、`|` 区切りの source 名だけを書いている
現行の配線には影響しない。

**2c. `fork` を matcher に含めている理由**(2026-08-01、公式 hooks docs
`code.claude.com/docs/en/hooks` で確認)。SessionStart の source は
`startup` / `resume` / `clear` / `compact` / `fork` の 5 値で、`fork` は
セッション複製(`--fork-session` + `--resume`/`--continue`、`/fork` の
バックグラウンド複製、`/branch`)で報告される。docs に
"Before v2.1.214, forked sessions reported source `resume`" と明記されており、
実際 host の 2.1.212 のバイナリ内の source 列挙は
`["startup","resume","clear","compact"]` で `fork` を含まない。

当時の host(2.1.212)では `fork` は一度も match しない代わりに、**足さない
まま CLI を 2.1.214 以上に上げると複製セッションで改変検知が一度も発火しなく
なる**状態だった(先に入れておけば穴が開く瞬間が来ない。issue #245 step 1)。

**その穴は現に閉じた(2026-08-04 実測、`claude` 2.1.220)**。同じ手順で
バイナリ内の source 列挙を読むと `["startup","resume","clear","compact","fork"]`
で、zod schema 側の `E.enum([...])` も同じ 5 値。**`fork` は現に報告されうる**
ので、matcher に足してある `fork` は今や実際に発火する枝である(step 1 を
step 2 より先にやった意味がここで確定した)。codex 側の
`SessionStartSource` は 4 値で `fork` を持たないため、`codex/hooks.json` は
`startup|resume|clear` のまま。

**2d. 両 harness とも `compact` を意図的に拾わない理由**。`compact` は
会話の継続であってセッションの開始ではなく、同じ警告を 1 セッション内で
繰り返すと warn-only の signal が摩耗する。`compact` は別 entry
(`session-compact-context.sh`)が担当している。

なお仮に拾っても `hooks-integrity-warn.sh` が 2 回走るわけではない
(2026-08-01 実測、同じ 2.1.212 のバイナリ。呼び出し側はマッチした
matcher group を集めて各 group の hooks を 1 回ずつ展開するだけなので、
group が別なら**それぞれの hook が 1 回ずつ**走る)。つまり
**避けたいのは二重発火ではなく警告の摩耗**。

**3. hook の stdout が `{` または `[` で始まると、警告は model の context に入らない**。
codex は `looks_like_json`(`codex-rs/hooks/src/engine/output_parser.rs`)でその 2 文字を
JSON 出力の合図とみなし、JSON としてパースできなければ run を `Failed` にして
`hook returned invalid session start JSON output` だけを残す。plain text が
additional context になるのは「JSON に見えない」出力のときだけ。
`agents/hooks/hooks-integrity-warn.sh` の警告ラベルが `[hooks-integrity]` ではなく
`hooks-integrity 警告:` なのはこのため(**Claude Code 側では素通しなので、
ラベルを戻しても codex 側でだけ静かに壊れる**。テストが stdout の先頭行を全文で
pin している — 1 文字目だけを見る形は、先頭に空行が入ると素通りする)。

なおこの制約は SessionStart 固有ではなく、codex に配線する hook 全般に及ぶ。
そのため 1 本ずつ踏んで直すのではなく、**配線前に構造で弾く**形にしてある
(issue #240): `scripts/lint-hook-stdout.sh` が `agents/hooks/` `claude/hooks/`
`codex/hooks/` の実体を横断で静的検査し、`echo` / `printf` のリテラルと heredoc
本文が `{` / `[` で始まっていたら `make test` を fail させる。同 issue で
`agents/hooks/session-compact-context.sh` のラベルも `[session-compact-context]`
から `session-compact-context:` に直した(**Claude Code 専用配線だったので実害は
出ていなかったが、codex へ配線した瞬間に踏む形だった**)。
ただし静的解析なので、拾えるのは**リテラルとして書かれた出力**だけ。変数展開経由の
出力(`printf '%s\n' "$x"`)や 1 行に複数の heredoc を開く形は見えない。現状その穴を
補っているのは hook ごとの実行時 pin で、`tests/session-compact/` と
`tests/hooks-integrity/` の 2 本に先頭行全文 pin がある(**新しく stdout を出す hook を
codex に配線するときは同じ pin を足すこと** — 自動では強制されない)。
linter の取りこぼしを見つけたら、`tests/lint-hook-stdout/` に `form_case` として
回帰ケースを足してから直す。

### scope 外(別 issue)

- codex CLI 側で notify を禁止する設定の有無は未調査
- `~/.codex/AGENTS.md` 経由の prompt injection は本層の対象外
- `~/.codex/skills/` は検知層の監視対象に含めていない。skill は model への
  指示テキストであって host が直接実行するものではなく、脅威モデルが異なる
  (prompt injection 側の問題として扱う)
