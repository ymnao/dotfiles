# 夜間ランナーの隔離方式

#432 の夜間ランナー (`claude -p` を launchd から無人で起動する) を、日常の macOS
ユーザーの資格情報から隔離する方式の決定 (#546)。無人用の設定ファイル・権限モード・
turn と時間の上限は #432 の決定事項が正本で、ここでは扱わない。

## 決定

**`claude -p` のプロセスを丸ごと sandbox-runtime (`srt`) で囲み、同じ macOS ユーザーで動かす。**
資格情報はランナー専用のものを環境変数で渡し、日常のものはファイルと Keychain の
両方を `denyRead` で塞ぐ。

- 公式は、権限の確認を外した無人実行を「container / VM / sandbox runtime」の中で動かすよう
  書いている (<https://code.claude.com/docs/en/sandbox-environments>)。この決定はその 3 つのうちの 1 つ
- Claude Code の組み込み sandbox は Bash 系のコマンドしか囲まない。Read / Edit / Write / WebFetch・
  command hook・ローカル MCP は sandbox の外で動く (<https://code.claude.com/docs/en/sandboxing.md>)。
  `srt` は親の `claude` ごと囲むので、hook や MCP のように claude が起動する子プロセスも中に入る (推定。
  「wraps an entire process」という記述からの読み取りで、hook を囲めたことはまだ実測していない)

## 選ばなかった方式

| 方式 | 選ばなかった理由 |
|---|---|
| 別の macOS ユーザー | Keychain は OS のレベルで分かれる。一方、この home は `drwxr-x---` で group が `staff` (2026-11-20 実測) なので、別ユーザーを `staff` に入れると `~/development` (755) が読めてしまう。home を 700 にする、ランナー用に dotfiles と各 repo を別に clone する、LaunchDaemon (`UserName` 指定、sudo で配置) に変える、の 3 つが要り、#432 の「LaunchAgent を `link.sh` で配線する」と食い違う。公式の推奨資料には載っていない |
| devcontainer / コンテナ | 対象 repo ごとに toolchain の image が要り、Docker を常に動かすことになる。dotfiles の hook を Linux で動かすことにもなる。公式は、コンテナの中の `~/.claude` の資格情報も持ち出されうると警告している (<https://code.claude.com/docs/en/devcontainer>) |
| macOS VM | 隔離はいちばん強い。ただ、直列の夜間 1 本に対して構築と保守が重い |

`srt` で足りなくなったら (下の「見直す条件」)、VM を次の候補にする。

## 前提の実測 (2026-11-20、`@anthropic-ai/sandbox-runtime@0.0.83`)

`srt` の README には、macOS の Keychain を遮断するかどうかの記載が無い。この方式は
「`srt` の中から日常の `gh` の token に届かない」ことに乗っているので、実装の前に確かめた。

| 設定の `denyRead` | 実行したもの | 結果 |
|---|---|---|
| (`srt` の外、対照) | `security find-generic-password -s gh:github.com` | exit 0 (`gh` の token は Keychain にある) |
| `~/.ssh` | 同上 | **exit 0 (届く)** |
| `~/.ssh` | `ls ~/.ssh` | `Operation not permitted`、exit 1 (設定は読まれている) |
| `~/.ssh`, `~/Library/Keychains` | `security find-generic-password -s gh:github.com` | `The specified item could not be found in the keychain.`、exit 44 |
| `~/.ssh`, `~/Library/Keychains` | `gh auth token` | exit 1 |

`srt` の既定の設定では、Keychain は塞がれない。`~/Library/Keychains` を `denyRead` に入れると
塞がる。そのため、**ランナーの `srt` の設定には `~/Library/Keychains` を必ず入れる。**
これは claude 自身の認証にも効くので、ランナーの claude は Keychain からは認証できない
(推定)。認証は次の節の環境変数で渡す。

## 資格情報

`srt` の外で動く起動スクリプト (#432 の `scripts/night-run.sh`) が資格情報を読み出し、環境変数で
`srt` の中へ渡す。中の agent からは、その値も読める。だから中に渡すのは、漏れても被害が
ランナーの範囲に収まるものだけにする。

| 用途 | 渡すもの | 置き場 (`srt` の外) |
|---|---|---|
| claude の認証 | `claude setup-token` で発行した `CLAUDE_CODE_OAUTH_TOKEN` | user の login keychain |
| GitHub | 対象 repo だけに絞った fine-grained PAT を `GH_TOKEN` に入れる。権限は Contents・Pull requests・Issues の write (ラベルとコメントに Issues が要る) | 同上 |

- 日常の `gh` 認証 (Keychain の `gh:github.com`) と `~/.ssh` は渡さない。push は HTTPS と
  `GH_TOKEN` で行う
- **「push はできて merge はできない」は、token の権限だけでは作れない。** fine-grained PAT では、
  push も PR の merge (`PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge`) も Contents の write
  に入っている (<https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens>。
  merge の行は、取得ツールの要約で読んだもの)。いまの main の ruleset (`protect main`) は
  `required_approving_review_count: 0` で、`bypass_actors` は空 (2026-11-20 実測)。つまり PR さえ
  あれば、PAT で merge できる
- merge を止めるには、required approvals を 1 以上にし、ランナーを user とは別の主体
  (GitHub App) にする必要がある。PR の作者は自分の PR を approve できない
  (<https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/approving-a-pull-request-with-required-reviews>)
  ので、user が自分の PR を merge するには、user を bypass に入れることになる。これは日常の
  merge の流れを変える。また、ruleset の bypass が PAT や App の操作にどう効くかは、docs に
  明記が無く未確認。だから初版は PAT で始め、merge は運用で防ぐ (#432 の非対話の `/dev` は
  merge の手順を持たない)。GitHub App への移行は「見直す条件」に置く

## 通信先

`srt` の `network.allowedDomains` で allowlist を持つ。`srt` の新しい設定形式は、独自の proxy を
まだサポートしていない (README)。そのため、package firewall などの proxy をつなぐ話とは
両立しない。proxy を入れるなら、設計からやり直す。

- 共通の許可先: `api.anthropic.com` / `github.com` / `api.github.com`。OAuth の
  `claude.ai` / `platform.claude.com` は、`CLAUDE_CODE_OAUTH_TOKEN` で起動できるなら外す
  (起動できるかは #432 の実装で確かめる)
- repo 固有のレジストリ (`registry.npmjs.org` など) は repo ごとに足す。置き場は #432 で決める
- ドメイン単位の許可なので、`github.com` を許せば、そこへの持ち出し (gist や他の repo への
  push) は防げない (README の Security limitations)。これを抑えるのは、`GH_TOKEN` の repo を
  絞ることの方

## ファイルシステム

- `denyRead`: `~` を丸ごと塞ぐ。そのうえで `allowRead` で、worktree の置き場・`~/.claude-night`・
  `~/.claude` (共有する skill / hook / rules / agents の symlink 先も含む)・dotfiles のチェックアウトだけを
  開ける。README では、読み取りは `allowRead` が `denyRead` より優先される
- `allowRead` が優先されるので、`~/Library/Keychains` や `~/.ssh` を含む親ディレクトリ
  (`~` や `~/Library`) を `allowRead` に書くと、この 2 つも開いてしまう。`allowRead` には葉に近いパスだけを書く
- `allowWrite`: worktree の置き場・`~/.claude-night` の状態ファイル・一時ディレクトリ (`/private/tmp`)
- `denyWrite`: `~/.claude-night/settings.json` と、共有する hook / skill の実体。書けると、次に
  sandbox の外で起動したセッションで実行されうる、と README が警告している
- claude の組み込み sandbox は、`srt` の中でもう一度 Seatbelt を張ることになる。動くかは
  未確認 (推測では動かない) なので、`~/.claude-night` の設定でどうするかは #432 の実装で決める

## 実機の確認手順

#432 のランナーが `srt` の設定を持った後、user のシェルで、ランナーと同じ `srt` の設定を
使って打つ。どれも読み取りだけ。

1. 対照: `srt` の外で `security find-generic-password -s gh:github.com >/dev/null` が exit 0
   になること (exit 0 にならない場合、手順 2 は判定に使えない)
2. `srt` の中で、同じコマンドが 0 以外になり、`gh auth token >/dev/null 2>&1` も 0 以外になること
3. `srt` の中で、`ls ~/.ssh` が `Operation not permitted` になること
4. `srt` の中で、対象外の repo (`~/development/` の別のディレクトリ) の `ls` が `Operation not permitted`
   になり、worktree の置き場の `ls` は成功すること (後者は `allowRead` が効いていることの対照)
5. `srt` の中で、`GH_TOKEN` を入れた `gh api user --jq .login` が成功すること。あわせて
   `gh repo view <対象外の repo>` が拒否されること (token の repo が絞れていることの確認)

1〜3 は、2026-11-20 に上の「前提の実測」で、`denyRead` が `~/.ssh` と `~/Library/Keychains` だけの
設定で通した。`~` を丸ごと塞ぐ設定ではまだ通していない。4 と 5 は、`allowRead` と専用の token が
できてからになるので、まだ通していない。

## #432 との接続

- 起動: LaunchAgent (#432 の決定のまま) → `scripts/night-run.sh` (`srt` の外で、資格情報の読み出し・
  選定・ラベル操作・worktree の作成) → issue ごとに `srt --settings <ランナー用の設定> claude -p ...`
- `srt` の設定ファイルは `claude-night/` に置く (#432 の「触ってよいファイル」の範囲)
- hook は claude の子プロセスとして `srt` の中で動く (推定)。sandbox の外へ出ることを前提にした
  hook (`excludedCommands` の `gh *` を当てにするものなど) は、中では日常の認証を持たない
- `srt` は beta で、設定形式は変わりうる (README)。そのため版を固定し、Brewfile 相当の宣言の
  置き場は #432 で決める

## 見直す条件

- `srt` の版を上げたとき: 「実機の確認手順」の 1〜3 を打ち直す。Keychain の扱いは README に
  書かれていないので、版によって変わりうる
- ランナーが merge まで進めた、または `GH_TOKEN` の範囲外へ書き込んだ事故があったとき:
  GitHub App と required approvals への移行を決める
- 夜間に並列で動かす (#511) とき、または対象 repo の信頼度が下がる (第三者の issue を
  `agent-ready` にする) とき: VM を再評価する
