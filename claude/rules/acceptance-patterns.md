---
paths:
  - "**/*.sh"
  - "**/*.bash"
  - "**/SKILL.md"
---

# 受理パターンと判定器の規約

入力を受理 / 拒否する判定を書くときの規約。`claude/rules/shell.md` から分離して
いるのは、**判定を書く場所が `.sh` に限らない**ため — skill の手順書 (`SKILL.md`)
は拡張子こそ `.md` だが、中のコマンドは agent がそのまま実行するので同じ危険を
持つ。`shell.md` 本体 (bash 3.2 互換 / クォート / shellcheck / locale pin など)
は `.md` を編集している最中には使い道が無いので、そちらは `.sh` 系のままにして
ある。

- **fail-closed にしたら、次は「受理パターンの広さ」を検査する**。「解析できない
  ものは fail にする」設計は*拒否側の既定*を安全にするだけで、*受理側*の口が
  広すぎれば素通りは残る。危険な入力が「解析できなかった」ではなく
  「**解析できてしまった**」経路で通るため、fail-closed にした安心感が
  そのまま盲点になる。受理パターンを書いたら、**それにマッチしてしまう危険な
  入力**を自分で構成して試す(マッチしない入力を試すだけでは足りない)。
  実例: issue #213 の対応で 2 周連続で踏んだ。1 周目は「command から repo 参照の
  断片を抽出して照合」する形で、断片が 1 つ取れると同じ command 内の他の参照が
  捨てられた(`bash "$A" && bash /tmp/evil.sh` の後半)。2 周目は受理パターン
  `^(bash|sh|...) "?([^"]+)"?$` の `[^"]+` が空白を含むため、クォート無しで
  書くと後続コマンドごと 1 個のパスとして吸い込まれ、前方一致で「監視対象内」と
  判定された。いずれも「未知の形は fail」という規約自体は満たしていた。
  実例: PR #331。ブランチ名の安全な文字集合を検査する `awk` を SKILL.md に
  書いたが、**判定器の exit code を敵対入力で測っていなかった**。`awk` の
  main rule の `exit` は END を実行し、END 側の `exit <expr>` が status を
  上書きするため (`printf 'x\n' | awk '{exit 7} END{exit 3}'` は 3)、
  `... {exit 1} END{exit NR!=1}` は 1 行入力なら何でも exit 0 になり
  `foo$(id);x` を受理していた。受理パターンを書いたら、**パターンだけでなく
  判定器の exit code も主張の一部**として両方向で測る
  (`tests/branch-name-validator/` が「修正後の式が敵対入力を reject する」
  ことを pin している。壊れた形そのものは pin していない)
- **外部由来の名前 (ref 名・PR title・package 名) をコマンド文字列に書き込まない**。
  git は ref 名に shell のメタ文字を許す (`git check-ref-format --branch 'foo$(id);x'`
  は exit 0)。この repo は public で、`/issue` は issue title からブランチ名を作るので、
  外部の文字列が名前に入る経路がある。二重引用符で囲んでも `$(...)` は展開されるので、
  クォートでは防げない。名前を渡さずに済むなら `HEAD` で済ませる
  (`git push origin HEAD` / `git rev-parse HEAD`)。名前が要るときの渡し方は次の 2 つに限る。
  (1) **出力側で突き合わせる**: `--head <name>` のように絞り込まず、全件を取って出力の
  行を比べる。
  (2) **git やファイルに名前を出させて、コマンド置換で渡す**:
  `"$(git branch --show-current)"` / `"$(cat "<scratchpad>/x.txt")"`。コマンド置換の
  *出力*は shell に再スキャンされないので、`$(...)` や `;` を含む名前でもリテラルな
  1 引数として届く (`printf '%s\n' "$(printf '%s' 'foo$(id);x')"` は `foo$(id);x` を出す)。
  危険なのは名前を**タイプし直す**ことで、git に名前を尋ねること自体ではない。
  ファイルに控える場合も、**読むのは shell** にする。要点は、名前がコマンド文字列を
  経由しないこと。git やスクリプトが書く経路 (`/next` の `merged-branch.txt`、
  `/dependabot-bulk` の `classified.json`) では、名前は LLM の出力も通らない。
  LLM が作った名前を tool で書く経路 (`/issue`) では、文字集合の検証と組にして
  「検証した文字列と実際に使う文字列が同じ」ことを保証する
- **一時ファイルの置き場: agent が打つ手順では `$TMPDIR` を裸で書く**。
  `WORK=$(mktemp -d "${TMPDIR:-/tmp}/x.XXXXXX")` は 2 つの理由で使えない。
  (1) Bash tool 呼び出し間で shell 変数は persist しないので次の呼び出しで
  `$WORK` は空になる。(2) `block-dangerous-commands.sh` の「動的展開を含む
  書き込み系リダイレクト」判定が residual から除去するのは `$TMPDIR` /
  `$HOME` / `$XDG_*` (と同名の `${...}` 形) だけなので、`> "$WORK/f"` も
  既定値つきの `> "${TMPDIR:-/tmp}/f"` もブロックされる (2026-09-02 実測)。
  スクリプト (`.sh`) 内では `mktemp -d` が正しい — 制約は agent が Bash tool
  から直接打つ形にだけ掛かる (`claude/rules/shell.md` の `mktemp` 項と対)。
  実例: `dependabot-bulk` skill は 2026-07-14 から 7 週間、この形で step 2 が
  実行不能なまま気付かれずにいた (issue #330 の対応中に判明)。
  **ただし `$TMPDIR` はセッションを分けない**。uid スコープの固定パス (実測:
  `/tmp/claude-501`) で、セッション ID も repo 名も含まないため、並走する別
  セッションの同じ手順が同じパスへ書く。**後の step で読み直して、検証済みと
  して扱うか破壊的操作へ渡す**一時ファイルは、`$TMPDIR` ではなく system prompt
  が示す scratchpad ディレクトリへ置き、**リテラルのパスで書く** (変数に入れると
  上のリダイレクト判定に掛かる)。閉じているのは権限ではなく非衝突で、write allow
  は `/tmp` 系を丸ごと許可しているので別セッションの scratchpad へも実際に書ける
  (2026-09-11 実測)。実例 2 つ: `/next` が step 1 で控えて step 3 で
  `git branch -d` へ渡す `merged-branch.txt`、`/issue` が step 7 で検証して
  step 9 で `git checkout -b` へ渡す `branch-name.txt`。**後者は入れ替わると
  検証そのものが空振りになる** — 検証した文字列と実際に使う文字列が別物になり、
  ゲートが「協力的な agent しか縛らない」状態へ戻る
- **ロードは適用の必要条件であって十分条件ではない。** この項の適用漏れは
  `*.sh` 側でも起きている (issue #284 は 3 周連続)。この rule が context に
  入っていることを「検査した」の代わりにしない
