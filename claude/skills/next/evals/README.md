# next skill evals

`/next` skill(merged 後の後始末: merged 確認 → main pull → ブランチ削除 →
handoff 更新 → 次タスク候補)の振る舞いテスト。共通の実行方法は
[`../../codex-review/evals/README.md`](../../codex-review/evals/README.md)、
branch 変数 / HANDOFF 退避の共通規約は [`../../dev/evals/README.md`](../../dev/evals/README.md)
を参照。このファイルは next 固有の共通スニペットを定義する。

## HANDOFF 保全検証(cksum)

`/next` は `/handoff` を呼び HANDOFF.md を更新する。恒久メモ節の消失や
異常経路での touch を検出するため、setup で checksum を記録し Pass
criteria で比較する:

```bash
before_cksum=$(cksum HANDOFF.md | awk '{print $1"_"$2}')
# ... eval 実行 ...
after_cksum=$(cksum HANDOFF.md | awk '{print $1"_"$2}')
# Pass criteria: [ "$before_cksum" = "$after_cksum" ]  # 異常経路で不変
```

`cksum` は POSIX 標準で BSD / GNU 両対応(memory `project_dotfiles_env_quirks.md`
の bash 3.2 / BSD tools 制約に整合)。`sha256sum` は GNU 専用なので使わない。

## merged 状態の再現(auto-delete 環境非依存化)

hosting 側で auto-delete が有効な環境でも eval を実行できるよう、setup で
fresh branch を毎回作成しローカル merge で merged 体裁を再現する:

```bash
git checkout main && git pull
branch="feature/eval-next-<name>-$(date +%s)"
git checkout -b "$branch"
echo x >> README.md && git commit -am "chore: eval fixture"
git checkout main
git merge --no-ff "$branch" -m "Merge $branch (eval fixture)"
git checkout "$branch"  # 対象ブランチに戻す
```

対象ブランチが `main` に merged で、かつ auto-delete で消えていない、と
いう状態を hosting 非依存に作れる。

## main SHA を意図的に古くする(next/04 用)

`git pull` の効果を検証するには main が最新でない状態が必要。`reset --hard`
は hook でブロックされる(memory `project_dotfiles_env_quirks.md`)ため
`branch -f` で回避する:

```bash
git checkout main && git pull
git checkout "$branch"           # main を非 checkout 状態にする
git branch -f main main~1        # main を 1 コミット戻す
git checkout main
before_main=$(git rev-parse HEAD)
```

## eval 一覧

- 01 — open PR で停止(HANDOFF cksum で不変を確認)
- 02 — closed-unmerged PR で停止(HANDOFF cksum で不変を確認)
- 03 — PR なしのブランチで停止
- 04 — merged happy path(main pull / branch 削除 / handoff)
- 05 — `git branch -d` が拒否されたら停止(`-D` フォールバック禁止)
- 06 — HANDOFF.md 恒久メモ節を保持

## fixtures

- `fixtures/handoff-template.md` — HANDOFF テンプレ(next/01, 02, 06)。
  ファイル名を `HANDOFF.md` にしない(gitignored のため)、setup 内 cp
  でのみ HANDOFF.md 化する
