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

**実測 (2026-08-03)**: メインは Opus 5 (`claude-opus-5`)、`code-reviewer`
サブエージェント(`model: opus`)も Opus 5 に解決された。根拠はどちらもセッションの
システムプロンプトが報告するモデル名で、**alias の解決先を実行基盤の外から検証した
ものではない**。この表は強制力を持たない — `claude/settings.json` にモデルを指定する
フィールドは無く(`effortLevel` のみ)、切り替えは `/model` か CLI 既定に依存する。
したがって表と実挙動の一致は、この実測でしか確かめられない。

`claude/agents/code-reviewer.md` の `model: opus` は **alias 運用が意図**で、
ID 直書きにはしない — alias は上流の世代交代に追随するので表の「Opus 世代」の
内側に収まる。逆に ID を固定すると世代が上がったときレビュアーだけが旧世代に
取り残される(ドリフトの向きが変わるだけ)。

**未解消: 現在レビュアーはメインと同一系統**(どちらも Opus 5)。下の「根拠」節と
`agents/AGENTS.md` が掲げる「生成者とレビュアーは同一モデル系統にしない」に
**現に反している**。cross-vendor の `codex-review` が別系統の第二意見を担うことで
実害は緩和されているが、Claude 側 reviewer だけを見れば規約違反のまま。
解消するには `code-reviewer` を別系統(Fable 世代)へ寄せる必要があるが、
frontmatter が完全なモデル ID / 別 alias を受け付けるかが未検証で、外れたときの
壊れ方(起動失敗か、黙って既定にフォールバックか)も分からない。

**確認する機会を 2 つに固定する**(「気づいたら」に委ねない):

- **§2 のチェックリストを回すとき** — 受理可否を 1 回試す(`model:` を別 alias に
  変えた `code-reviewer` を軽いプロンプトで起動し、自分の実行モデル名を報告させる)。
  受け付けると分かった時点で別系統への移動を再検討する
- **`codex-review` が恒常的に使えなくなったとき** — 緩和が消えるので即座に見直す。
  `/pr` は codex 不能時に Fable 系サブエージェントで代替する設計なので、その
  フォールバックが常態化していたらこれに当たる

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
- [ ] skill eval を全件実行(移行先の世代で pr / issue / resolve /
      codex-review 各 3 本以上)し、壊れた skill を特定して修正する
- [ ] `make test`(hook 回帰テスト込み)を実行して基線を確認する
- [ ] 最初の 1 週間、レビュー指摘の見逃し・skill の手順飛ばしを意識的に
      観察し、気づきを CLAUDE.md / skill に反映する(下記 3)
- [ ] 移行元の世代に固有の記述が設定に残っていないか確認する
      (例: `grep -ri fable claude/ codex/ agents/`)
- [ ] **§1 の実測注記を更新する**(モデル名・ID・測定日)。ズレに気づく
      唯一の手がかりなので、ここを更新しないと世代レベル記述の意味が薄れる
- [ ] **agent frontmatter が完全なモデル ID / 別 alias を受け付けるか試す**
      (§1「未解消」の確認機会。受け付けるなら `code-reviewer` を別系統へ
      寄せることを再検討し、結果を §1 に反映する)

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

2026-07-03 の検討(HANDOFF.md 候補 1〜10)で見送りを決めたもの。
先回りで入れず、条件を満たしたら再評価する。

| 機構 | 見送り理由 | 再評価条件 |
|---|---|---|
| GitHub Actions 連携(claude-code-action) | API 従量課金が必要(x20 定額の外)。ローカルレビューと重複。prompt injection 前提の運用が必要 | 他者コントリビュータのいるリポを持ったとき |
| Agent teams | 実験的で既知制限が多い(再開不可・ネスト不可等)。サブエージェントで足りる | GA になり、並列レビュー等で実需が出たとき |
| opusplan | plan mode を計画の境界として使っていない(セッション+仕様書で分離する運用)。/model で随時有効化できる | plan mode 中心の運用に変わったとき |
| Superpowers(obra/superpowers) | 公式マーケットプレイス外で全文監査が必要。既存 skill 群と思想が重複。更新追従がない | 同種の困りごとが 3 回起きたとき、または公式マーケットプレイス入りしたとき(その skill だけ監査して取り込む) |
| keybindings カスタマイズ | 現時点で困っている操作がない | 操作の不満が具体化したとき |
| Stop hook 駆動の review 強制ループ(claude-review-loop 系) | /dev 内の有界レビューループ(上限 2 周)で足りる。無限ループ対策(`stop_hook_active` guard)が必要になり、停止タイミングの監視性も下がる | /dev 運用でレビュー飛ばしが実際に起きたとき |
| Ralph loop 型の外側無人ループ(`while true; claude -p` 系) | merge ゲート・plan ゲートの人間監視を放棄することになる。2026-07-19 の検討で「パイプライン圧縮 + 人間ゲート再配置」(/dev + /next)を採用 | 完全無人で回してよい種類の反復タスク(大量 migration 等)が実際に発生したとき |

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
| 二次: hook (Bash) | `agents/hooks/block-dangerous-commands.sh` の「書き込み文脈 + `.codex` component」判定 | tilde / `$HOME` / 絶対パス表記のいずれでも、path token に `.codex` component が現れる書き込みを block(読み取りは allow のまま) | `cd ~/.codex && printf x > config.toml` のように **書き込み segment 側に `.codex` component が現れない形**(一次防御が担当) |
| 二次: hook (file 編集) | `agents/hooks/guard-codex-dir.sh` の `is_protected_home_codex_config` 判定 | Edit / Write / MultiEdit / NotebookEdit / apply_patch が `~/.codex/config.toml` を指す場合(tilde / `$HOME` / `${HOME}` / 絶対パス / `..` 経由 / 大文字表記を正規化して比較) | `~/.codex/` 配下の他ファイル(`sessions/` / `auth.json` 等は codex CLI が正当に書くため意図的に allow) |
| 正規の書き込み経路 | `scripts/codex-merge-config.sh` を **ユーザーが手動実行**(sandbox 外) | repo の `codex/config.toml` を正本として `~/.codex/config.toml` へマージ | — |

一次と二次が担当する経路は**意図的に非対称**。Bash 経路は sandbox が包括的に止め、
file 編集 tool 経路は sandbox が効かないので hook が止める。片方だけでは穴が残る。

- 一次防御の regression は `tests/integrity/verify-settings-codex-domains.sh`
  (+ `run-integrity-selftest.sh` の tamper fixture)が assert する
- 二次防御 (Bash) の regression は `tests/hooks/block-dangerous-commands.cases.jsonl`
  の `home-codex-config-*` / `tilde-codex-config-*` ケースが pin する
- 二次防御 (file 編集) の regression は `tests/hooks/guard-codex-dir.cases.jsonl` の
  `{{HOME}}/.codex/config.toml` 系ケースが pin する(allow 側のラチェットも含む)

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
除外を「単独コマンドのときだけ」に絞る指定方法は上流に存在しない(2.1.212 時点)。
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

**2c. `fork` を matcher に含めている理由**(2026-08-01、公式 hooks docs
`code.claude.com/docs/en/hooks` で確認)。SessionStart の source は
`startup` / `resume` / `clear` / `compact` / `fork` の 5 値で、`fork` は
セッション複製(`--fork-session` + `--resume`/`--continue`、`/fork` の
バックグラウンド複製、`/branch`)で報告される。docs に
"Before v2.1.214, forked sessions reported source `resume`" と明記されており、
実際 host の 2.1.212 のバイナリ内の source 列挙は
`["startup","resume","clear","compact"]` で `fork` を含まない。

つまり**今の host では一度も match しない代わりに、足さないまま CLI を
2.1.214 以上に上げると複製セッションで改変検知が一度も発火しなくなる**。
先に入れておけば穴が開く瞬間が来ない(issue #245 step 1)。codex 側の
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
