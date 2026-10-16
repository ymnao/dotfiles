---
paths:
  - "**/*.sh"
  - "**/*.bash"
---

# dotfiles 固有のシェル規約

この repo のパス・道具・コードベースの性質を前提にする規約を含む項目。実例だけが dotfiles 由来の項目は
`claude/rules/shell.md` (全 repo 共通) に置く (分割は項目単位)。

- **`agents/hooks/` (と `claude/hooks/` `codex/hooks/` の実体) は編集中の状態がそのまま
  live に効く** (`~/.claude/hooks/` 等からの symlink 経由)。途中で hook が壊れると
  Bash / Edit / Write がすべて block され、agent 自身では戻せない。編集は scratchpad に
  コピーして行い、`HOOK_DIR=<コピー先の絶対パス> bash tests/run-hook-tests.sh …` と
  通常の payload の smoke test を通してから、`cp` で 1 回で正本に置き換える。壊れたときの
  復旧は Terminal パネル (`run_in_terminal`) か user の手で `git restore <hook>`。
  実例: issue #381 (未定義の関数を呼ぶ行を先に入れ、全ツールが止まった)
- **hook 自身を調べるとき、guard に阻まれても回避形を組み立てない**。この repo の
  hook は自分が打つ Bash コマンドも検査するので、テストに使いたい入力がそのまま
  自分の guard に引っ掛かる。文字列を分割・連結して通すと、目的が正当でも防御機構の
  回避で、「回避できた」観測だけが残る。測りたい入力は `tests/run-hook-tests.sh`
  経由か、payload をファイルに書いてから hook に流す。それでも測れないなら
  「この形は測れなかった」と報告する — **未測定の報告は無害だが、回避は防御
  そのものを壊す**。`agents/hooks/` を触る PR のレビュー依頼には毎回この指示を含める
  (`claude/agents/code-reviewer.md` からこの項を指している)。
  実例: issue #308 のレビューで code-reviewer が payload を分割連結して guard を回避した
- **codex に配線する hook の stdout は `{` / `[` で始めない**。codex は hook の
  stdout がその 2 文字で始まると JSON 出力とみなし、パースに失敗した時点で run を
  `Failed` にして**本文を model の context に入れない**(実測根拠は
  dotfiles の docs/ai-operations.md §10)。Claude Code 側は素通しなので、**片方の harness でだけ
  静かに壊れる**形になる。防御は 2 層で、**どちらも必要**(issue #240):
  - **静的**: `scripts/lint-hook-stdout.sh` が `agents/hooks/` `claude/hooks/`
    `codex/hooks/` を横断検査し、`make test` を fail させる。拾えるのは
    **リテラルとして書かれた出力**だけ
  - **実行時**: 変数展開経由の出力は静的には見えないので、hook ごとに
    **stdout 単独 (`2>&1` で取らない) で先頭行を全文 pin** する
    (実例: `tests/session-compact/` `tests/hooks-integrity/`)。
    **新しく stdout を出す hook を codex に配線するときは pin を足す** —
    自動では強制されない
  linter が取りこぼす形を見つけたら、`tests/lint-hook-stdout/` に `form_case` で
  回帰ケースを足してから直す。取りこぼしの既知の形は linter 冒頭コメントにある
- **mutation 規約** (2 点目は本体を一括置換で編集するときも同じ):
  - **1 回に 1 変数だけ変える**。複数変えた mutant が FAIL しても、どの変数が
    検出されたのか特定できず誤った因果をコメントに残す
    (実例: issue #218)
  - **適用したら「実際に変わった行」を `git diff` で数える**。この repo は設計コメントが
    厚く、置換がコメント行に当たって空振りすると「テストが検出できなかった」という
    偽陰性になる。逆に同型ブロックが複数あるので**当たりすぎ**も起き、こちらは
    別の理由でテストが緑になるぶん見つけにくい
    (実例: issue #232 の空振り、issue #291 の過剰適用)
  - **戻すのに `git checkout <file>` を使わない**。同居する未 commit の本編集も消える。
    当てたときと同じ置換の逆向きで戻し、`git diff` が適用前と一致することで確認する。
    本編集を先に commit してから当てれば衝突自体が起きない (実例: issue #288)
