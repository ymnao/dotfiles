# 夜間ランナーの隔離方式

#432 の夜間ランナー (`claude -p` を launchd から無人で起動する) を、日常の macOS
ユーザーの資格情報から隔離する方式の決定 (#546)。無人用の設定ファイル・権限モード・
turn と時間の上限は #432 の決定事項が正本で、ここでは扱わない。

## 決定

**`claude -p` のプロセスを丸ごと sandbox-runtime (`srt`) で囲み、同じ macOS ユーザーで動かす。**
`~` を丸ごと `denyRead` で塞ぎ、ランナーに要るパスだけを `allowRead` で開ける。資格情報は、
ランナー専用のものを環境変数で渡す。

- 公式は、権限の確認を外した無人実行を「container / VM / sandbox runtime」の中で動かすよう
  書いている (<https://code.claude.com/docs/en/sandbox-environments>)。この決定はその 3 つのうちの 1 つ
- Claude Code の組み込み sandbox は Bash 経路しか囲まない (実測は [ai-operations.md §10](ai-operations.md#denyread-の実測--glob-は効くが削除リネームまで止まる))。
  `srt` は親の `claude` ごと囲むので、hook や MCP のように claude が起動する子プロセスも中に入る (推定。
  「wraps an entire process」という記述からの読み取りで、hook を囲めたことはまだ実測していない)

## 選ばなかった方式

| 方式 | 選ばなかった理由 |
|---|---|
| 別の macOS ユーザー | Keychain は OS のレベルで分かれる。一方、この home は `drwxr-x---` で group が `staff` (2026-11-20 実測) なので、別ユーザーを `staff` に入れると `~/development` (755) が読めてしまう。home を 700 にする、ランナー用に dotfiles と各 repo を別に clone する、LaunchDaemon (`UserName` 指定、sudo で配置) に変える、の 3 つが要り、#432 の「LaunchAgent を `link.sh` で配線する」と食い違う。公式の推奨資料には載っていない |
| devcontainer / コンテナ | 対象 repo ごとに toolchain の image が要り、Docker を常に動かすことになる。dotfiles の hook を Linux で動かすことにもなる。公式は、コンテナの中の `~/.claude` の資格情報も持ち出されうると警告している (<https://code.claude.com/docs/en/devcontainer>) |
| macOS VM | 隔離はいちばん強い。ただ、直列の夜間 1 本に対して構築と保守が重い |

## 前提の実測 (2026-11-20、`@anthropic-ai/sandbox-runtime@0.0.83`)

`srt` の README には、macOS の Keychain を遮断するかどうかの記載が無い。組み込み sandbox の中からは
Keychain が届かない ([ai-operations.md §10](ai-operations.md#sandbox-の-excludedcommands-が一次防御を丸ごと外す経路)
の `gh auth status` の実測) が、`srt` も同じとは限らないので、実装の前に確かめた。

| 設定の `denyRead` | 実行したもの | 結果 |
|---|---|---|
| (`srt` の外、対照) | `security find-generic-password -s gh:github.com` | exit 0 (`gh` の token は Keychain にある) |
| `~/.ssh` | 同上 | **exit 0 (届く)** |
| `~/.ssh` | `ls ~/.ssh` | `Operation not permitted`、exit 1 (設定は読まれている) |
| `~/.ssh`, `~/Library/Keychains` | `security find-generic-password -s gh:github.com` | `The specified item could not be found in the keychain.`、exit 44 |
| `~/.ssh`, `~/Library/Keychains` | `gh auth token` | exit 1 |

`srt` は、Keychain をファイル (`~/Library/Keychains`) の読み取りとして塞ぐ。そのため、`denyRead` が
`~/Library/Keychains` を覆っていることが、この方式の前提になる。`~` を丸ごと塞げば覆えるが、
`~` での確認はまだしていない (「実機の確認手順」)。home の外 (`/Library/Keychains` など) は `~` では
覆えないので、別に確かめる。claude 自身の認証も Keychain からは読めなくなる (推定) ので、
次の節の環境変数で渡す。

## 資格情報

`srt` の外で動く起動スクリプト (#432 の `scripts/night-run.sh`) が資格情報を読み出し、環境変数で
`srt` の中へ渡す。中の agent からは、その値も読める (起動後のプロセスが持つ環境変数を剥がせない
ことは [ai-operations.md §10](ai-operations.md#sandbox-の外側の-credential-保護--scrub-は入れない298))。
だから中に渡すのは、漏れても被害がランナーの範囲に収まるものだけにする。

| 用途 | 渡すもの | 置き場 (`srt` の外) |
|---|---|---|
| claude の認証 | `claude setup-token` で発行した `CLAUDE_CODE_OAUTH_TOKEN` | user の login keychain |
| GitHub | 対象 repo だけに絞った fine-grained PAT を `GH_TOKEN` に入れる。権限は Contents・Pull requests・Issues の write (ラベルとコメントに Issues が要る) | 同上 |

- 日常の `gh` 認証 (Keychain の `gh:github.com`) と `~/.ssh` は渡さない。push は HTTPS と
  `GH_TOKEN` で行う
- **PAT では merge を権限で止められない。初版は PAT で始め、merge は運用で防ぐ** (#432 の非対話の
  `/dev` は merge の手順を持たない)。fine-grained PAT では、push も PR の merge も Contents の
  write に入っている (<https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens>。
  merge の行は要確認)。いまの main の ruleset (`protect main`) は `required_approving_review_count: 0`、
  `bypass_actors` が空 (2026-11-20 実測) なので、PR があれば merge できる。権限で塞ぐ案は「見直す条件」に置く

## 通信先

`srt` の `network.allowedDomains` で allowlist を持つ。`srt` の新しい設定形式は、独自の proxy を
まだサポートしていない (README)。package firewall などの proxy を入れるなら、設計からやり直す。

- 共通の許可先は `api.anthropic.com` / `github.com` / `api.github.com`。これに repo 固有のレジストリ
  (`registry.npmjs.org` など) を repo ごとに足す
- ドメイン単位の許可なので、`github.com` を許せば、そこへの持ち出し (gist や他の repo への
  push) は防げない (README の Security limitations)。これを抑えるのは、`GH_TOKEN` の repo を
  絞ることの方

## ファイルシステム

- `denyRead` は `~` を丸ごと塞ぐ。`allowRead` では、worktree の置き場・`~/.claude-night`・`~/.claude`・
  dotfiles のチェックアウト (共有する skill / hook / rules / agents の symlink 先) だけを開ける。
  `allowRead` は `denyRead` に優先する (README) ので、`~/Library/Keychains` や `~/.ssh` を含む親
  (`~` や `~/Library`) は書かず、葉に近いパスだけを書く
- `allowWrite` は、worktree の置き場・`~/.claude-night`・一時ディレクトリ (`/private/tmp`)。dotfiles は
  入れないので、共有する hook / skill の実体には書けない
- `denyWrite` は `~/.claude-night/settings.json`。書けると、次に sandbox の外で起動したセッションで
  実行されうる、と README が警告している

## 実機の確認手順

#432 のランナーが `srt` の設定を持った後、user のシェルで、ランナーと同じ `srt` の設定を使って打つ。
どれも読み取りだけ。1 は 2 の対照なので先に打つ。2〜4 は互いに依存しないので、`srt -c` 1 回にまとめてよい。

1. `srt` の外で `security find-generic-password -s gh:github.com >/dev/null` が exit 0 になること
   (exit 0 にならない場合、2 は判定に使えない)
2. `srt` の中で、同じコマンドが 0 以外になり、`gh auth token >/dev/null 2>&1` も 0 以外になること
3. `srt` の中で、`ls ~/.ssh` が `Operation not permitted` になること
4. `srt` の中で、対象外の repo (`~/development/` の別のディレクトリ) の `ls` が `Operation not permitted`
   になり、worktree の置き場の `ls` は成功すること (後者は `allowRead` が効いていることの対照)
5. `srt` の中で、`GH_TOKEN` を入れた `gh api user --jq .login` が成功し、`gh repo view <対象外の repo>`
   は拒否されること (token の repo が絞れていることの確認)

1〜3 は「前提の実測」で、`denyRead` が `~/.ssh` と `~/Library/Keychains` だけの設定で通した。`~` を
丸ごと塞ぐ設定での 1〜3 と、4・5 はまだ通していない。

## #432 に委ねる事項

- 起動の形: LaunchAgent (#432 の決定のまま) → `scripts/night-run.sh` (`srt` の外で、資格情報の読み出し・
  選定・ラベル操作・worktree の作成) → issue ごとに `srt --settings <ランナー用の設定> claude -p ...`。
  `srt` の設定ファイルは `claude-night/` に置く
- `srt` の版の固定と、その宣言の置き場。`srt` は beta で、設定形式は変わりうる (README)
- repo 固有のレジストリを許可する置き場と、`CLAUDE_CODE_OAUTH_TOKEN` で起動できるときに OAuth 用の
  `claude.ai` / `platform.claude.com` を許可先から外せるか
- claude の組み込み sandbox を `srt` の中で使うか。中でもう一度 Seatbelt を張ることになり、動くかは
  未確認 (推測では動かない)
- hook は claude の子プロセスとして `srt` の中で動く (推定) ので、sandbox の外へ出ることを前提にした
  hook (`excludedCommands` の `gh *` を当てにするものなど) は、中では日常の認証を持たない。その扱い

## 見直す条件

- `srt` の版を上げたとき: 「実機の確認手順」の 1〜3 を打ち直す
- ランナーが merge まで進めた、または `GH_TOKEN` の範囲外へ書き込んだ事故があったとき: 権限で塞ぐ
  形へ移る。候補は次の 2 つで、どちらも未確認
  - GitHub App に required approvals を組み合わせる。PR の作者は自分の PR を approve できない
    (<https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/approving-a-pull-request-with-required-reviews>)
    ので、user が自分の PR を merge するには user を bypass に入れることになり、日常の merge の流れが変わる
  - push を repo 単位の deploy key に、`GH_TOKEN` を Contents read に分ける
- 夜間に並列で動かす (#511) とき、または対象 repo の信頼度が下がる (第三者の issue を
  `agent-ready` にする) とき: VM を再評価する
