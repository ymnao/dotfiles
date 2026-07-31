# AI 運用ガイド

人間(自分)向けの運用ドキュメント。モデルが毎セッション読む AGENTS.md には
入れない(コンテキスト節約のため。確実に実行させたいルールは hook に、
毎セッション必要な最小ルールだけ AGENTS.md にある)。

## 1. モデル運用(役割分担)

AGENTS.md「モデル分担ルール」節の最小規範を、こちらで役割・モデル対応・
根拠込みに詳細化する。

| 役割 | モデル | effort | 用途 |
|---|---|---|---|
| メイン(統括・意思決定) | Opus 4.7(**4.8 は使わない**) | high(難所は xhigh) | 全体制御・decisions・並列調整・軽 verify・PR 作成 |
| **plan 立案**(非自明タスク) | **Fable** | - | `/dev` step 2 の変更ファイル・実装手順・考慮点の立案。self-preference bias 回避 + 推論深度確保のためメイン Opus からサブエージェント委譲 |
| 実装ループ(詳細 plan あり) | Sonnet 5 | high(難所は xhigh) | ファイル/関数/追加行の意図まで指定された実装、機械的 refactor、テスト追加 |
| 並列 fan-out(中軽度並列) | Sonnet 5 | high | /simplify の観点別 finder、多点調査 |
| 独立第二意見(別モデル系統) | Fable など | - | fresh context のレビュー、難しい設計判断、cascade でメインが疑わしいと判定したときのエスカレーション先 |
| 探索・情報収集 | Haiku 4.5 | - | 軽い調査・ファイル探索 |

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

## 2. Fable 5 → 下位モデル移行チェックリスト

移行日に実施:

- [ ] `claude/settings.json` の `effortLevel` を見直す(現行 "high"。
      Opus 4.8 / Sonnet 5 の高難度タスクは xhigh が公式推奨。まず high 維持
      + 難所で引き上げの運用から始め、質が足りなければ既定を上げる)
- [ ] skill eval を全件実行(Sonnet 5 で pr / issue / resolve /
      codex-review 各 3 本以上)し、壊れた skill を特定して修正する
- [ ] `make test`(hook 回帰テスト込み)を実行して基線を確認する
- [ ] 最初の 1 週間、レビュー指摘の見逃し・skill の手順飛ばしを意識的に
      観察し、気づきを CLAUDE.md / skill に反映する(下記 3)
- [ ] Fable 専用の記述が設定に残っていないか確認する
      (`grep -ri fable claude/ codex/ agents/`)

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
一切含まない**。codex CLI **0.145.0** で実測して確認した(issue #207)。

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
   `trusted_hash` 6 件のうち **5 件をバイト一致で再現**した(残る 1 件は Stop
   event の default timeout が未特定なだけ)。再現できた payload の例:

   ```
   {"event_name":"pre_tool_use","hooks":[{"async":false,"command":"bash \"$HOME/.codex/hooks/block-dangerous-commands.sh\"","statusMessage":"コマンド安全性チェック中...","timeout":10,"type":"command"}],"matcher":"^Bash$"}
   → sha256:926d8278e318187e63816360f984fd354cad9dec305d9e7f4154a02377b3f39d
   ```

**帰結**: `~/.codex/hooks/*.sh` の中身を差し替えても codex は再承認を求めず、
次回起動時に無警告で host 側で実行する。**codex 側の hook 承認機構は
スクリプト改変に対する backstop にならない**。逆に、`hooks.json` の
command 文字列・matcher・timeout・statusMessage を変えると hash が変わり
再承認が要る(実際 `codex/hooks.json` に hook を追加した直後は、その entry が
Untrusted となり承認するまで実行されない)。

この結論は codex の実装詳細に依存するため、**codex を upgrade したら再実測する**
(本節にバージョンを明記してあるのがその trigger)。

**2026-07-31 時点で host は 0.146.0 に上がっており、この trigger は発火済みだが
trusted_hash の再実測はまだ行っていない**(上の記述は 0.145.0 での測定のまま)。
再実測は issue #214 が担当する。本節の下流の判断(「承認するまで発火しない」
「スクリプト本体は hash に入らない」)は 0.145.0 の測定に依存している点に注意。

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
| 検知 (session, Claude Code) | `agents/hooks/hooks-integrity-warn.sh` を `claude/settings.json` の SessionStart (`startup\|resume\|clear`) に配線 | セッション開始時に、監視対象の未コミット改変を警告として context に注入する。**自動で発火する経路**(model の context に入り、人は transcript で確認できる) | 警告のみで遮断はしない(dotfiles 開発中は dirty が正常状態のため意図的に warn-only)。**codex 単体の作業では発火しない**(下の行が担当) |
| 検知 (session, codex) | 同 hook を `codex/hooks.json` の SessionStart (`startup\|resume\|clear`) に配線(issue #215)。`codex/hooks/hooks-integrity-warn.sh` は正本への相対 symlink | **(codex TUI で承認された後に限り)** codex CLI 単体で作業する経路。本節の脅威モデルの中心は codex 側なので、ここが塞がって初めて主要経路が覆われる | 同上(warn-only)。加えて **承認するまで発火しない** — 新 entry は trusted_hash 未登録で Untrusted 扱いになる(承認は host 側の user 操作で、agent からは行えない) |
| 検知 (手動) | 同 hook を `make test` と `tests/run-gate.sh`(`make gate`)からも呼ぶ | **手で `make test` / `make gate` を叩いたとき**の表示 | **Stop hook 経由では表示されない** — `stop-verify-gate.sh` は gate の出力を変数に capture し、gate が通れば捨て、落ちても `tail -20` しか出さないため。ターンごとの自動検知にはなっていない |
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

### codex 側 SessionStart hook の実測結果(この節が正本)

**codex 側の記述**はすべて **2026-07-31 に upstream の tag `rust-v0.146.0`
(host の codex-cli 0.146.0)のソースを読んで確認**した(実際に codex を起動して
発火させた観測ではない — 本節の配線は執筆時点で未承認のため)。
hook 本体とテストのコメントはこの節を指すだけに留めてある(同じ実測事実を複数箇所に
書くと、codex の upgrade で挙動が変わったときに片方だけ更新されて食い違うため)。
**codex を upgrade したら §10 冒頭の trusted_hash とあわせてここも再確認する**。

**Claude Code 側の挙動は実装非公開のため同じようには確認できない**。以下で
「Claude Code 側では素通し」と書いているのは、この repo での運用上の観測
(SessionStart hook の stdout がそのまま context に入っており、JSON 風かどうかで
落ちた例が無い)に基づく。codex 側の記述と根拠の強さが違う点に注意。

**1. matcher は SessionStart でも有効**。突合対象は `SessionStartSource` の
`startup` / `resume` / `clear` / `compact`。matcher が無視される(実装上
`matcher_pattern_for_event` が `None` を返す)のは **`UserPromptSubmit` と `Stop` の
2 イベントだけ**(`codex-rs/hooks/src/events/common.rs`、同 `session_start.rs`)。

**2. matcher の突合方式は 2 通りに分岐する**(同 `common.rs` の `matches_matcher`)。
Claude Code の regex 一本槍とは違うので、ここを取り違えるとテストだけが通る:

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
現時点で `agents/hooks/session-compact-context.sh` は `[` 始まりの stdout を出すが、
Claude Code 専用配線なので実害は無い(codex へ配線するときに踏む。issue で追跡)。

### scope 外(別 issue)

- codex CLI 側で notify を禁止する設定の有無は未調査
- `~/.codex/AGENTS.md` 経由の prompt injection は本層の対象外
- `~/.codex/skills/` は検知層の監視対象に含めていない。skill は model への
  指示テキストであって host が直接実行するものではなく、脅威モデルが異なる
  (prompt injection 側の問題として扱う)
