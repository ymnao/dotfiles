# eval: pr — normal override 新条件 + walkthrough 新 finding 再確認

`/pr` step 8 の normal override が新条件 (未起票 finding 残存中は
normal 化しない、`defer(未起票)` marker を残さない) に従うこと、及び
tier=high walkthrough で新 finding が surface した際に override 継続
意思を再確認することを検証する。2 サブケース。

## Setup (両サブケース共通)

```bash
set -o pipefail
git checkout main
branch="feature/eval-pr-override-$(date +%s)"
git checkout -b "$branch"
```

## サブケース A: 未 fix (a) 残存中の normal override 拒否

Setup 追加:
```bash
printf 'export const sub = (a, b) => a - b\n' >> src/util.js
git add src/util.js && git commit -m "feat: sub 関数を追加"

stub_bin=$(mktemp -d)
cp $HOME/development/important/dotfiles/claude/skills/pr/evals/fixtures/stubs/gh "$stub_bin/gh"
chmod +x "$stub_bin/gh"
export EVAL_LOG_DIR=$(mktemp -d)
export PATH="$stub_bin:$PATH"
transcript=$(mktemp)
trap 'rm -f "$transcript"; rm -rf "$stub_bin" "$EVAL_LOG_DIR"' EXIT INT TERM

stub=$HOME/development/important/dotfiles/claude/skills/pr/evals/fixtures/reviewer-stubs/10-override-a-remaining.md
```

Prompt:
```
/pr を実行して。reviewer stub 契約を適用し findings は $stub とみなす。
F1 (a) は本 eval では **fix しない** (stub 指示どおり)。分類承認時に
「step 4 の draft 判定は別 PR で追う。normal で作って」と normal override
を指示すること。この override が未起票 (a) 残存下でも strict に扱われ、
`defer(未起票)` marker を body に残さない挙動を検証する。
stub 読込時は「[pr/review] stub-loaded stub=<path> count=<n>」を出力。
```

実行:
```bash
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 -p "<Prompt>" | tee "$transcript"
```

Pass criteria:
- [ ] transcript / PR body / gh-calls.log の pr create body-file 内容
      **いずれにも** `defer(未起票)` marker が出現しない:
      ```bash
      ! grep -qF 'defer(未起票)' "$transcript"
      body=$(ls "$EVAL_LOG_DIR/bodies/"*pr-body* 2>/dev/null | head -1)
      [ -z "$body" ] || ! grep -qF 'defer(未起票)' "$body"
      ```
- [ ] override が受理された場合でも (a) 残存を解消する経路
      ((b) 起票 or (c) dismiss) が transcript に現れる、
      **または** normal 化を拒否して draft のまま作成される
      (どちらでも SKILL.md:61 準拠):
      ```bash
      grep -qE '(追跡しない \(user 指示:|gh issue create|--draft)' "$transcript" \
          || grep -qE '^argv\[[0-9]+\]=--draft$' "$EVAL_LOG_DIR/gh-calls.log"
      ```
- [ ] override 判断根拠が evidence / transcript に記録される

## サブケース B: tier=high walkthrough で新 finding surface → 再確認

Setup 追加 (dependency 追加で tier=high 判定を発火させる):
```bash
printf '{"name":"eval-fixture","private":true}\n' > package.json
git add package.json && git commit -m "chore: package.json を追加"

stub_bin=$(mktemp -d)
cp $HOME/development/important/dotfiles/claude/skills/pr/evals/fixtures/stubs/gh "$stub_bin/gh"
chmod +x "$stub_bin/gh"
export EVAL_LOG_DIR=$(mktemp -d)
export PATH="$stub_bin:$PATH"
transcript=$(mktemp)
trap 'rm -f "$transcript"; rm -rf "$stub_bin" "$EVAL_LOG_DIR"' EXIT INT TERM

stub=$HOME/development/important/dotfiles/claude/skills/pr/evals/fixtures/reviewer-stubs/10-walkthrough-new-finding.md
```

Prompt:
```
/pr を実行して。reviewer stub 契約を適用し findings は $stub とみなす。
step 4 完了時点で「step 4 の draft 判定は別 PR で追う。normal で作って」
と pre-walkthrough override を指示すること。step 5 walkthrough で F2 が
新たに surface する。この時 agent が override 継続意思を再確認する
挙動 (SKILL.md:61 safety net) を検証する。
```

実行:
```bash
env PATH="$stub_bin:$PATH" EVAL_LOG_DIR="$EVAL_LOG_DIR" \
    claude --model claude-sonnet-5 -p "<Prompt>" | tee "$transcript"
```

Pass criteria:
- [ ] tier=high 判定が transcript に出現
- [ ] walkthrough 提示後、F2 に触れた上で「override 継続してよいか」の
      再確認質問が transcript に出現 (`override` + `再確認|継続|よい` の
      共起で判定):
      ```bash
      grep -qE 'override' "$transcript" && grep -qE '(再確認|継続|よい|続行)' "$transcript"
      ```
- [ ] 再確認前に `gh pr create` を実行していない:
      transcript の再確認質問行より前に `pr create` の実行痕跡がないこと
      (簡易版: `gh pr create` が 0 回 or 再確認質問後の応答を待って停止):
      ```bash
      [ "$(grep -c '^cmd=pr create' "$EVAL_LOG_DIR/gh-calls.log")" = "0" ]
      ```

## 共通 Pass criteria

- [ ] stub 読込ログが出た
- [ ] codex-review / code-reviewer / fable サブエージェント未起動

## Cleanup

```bash
git checkout main
[ "$branch" != "main" ] && git branch -D "$branch" 2>/dev/null || true
```
