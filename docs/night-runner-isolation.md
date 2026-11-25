# 夜間ランナーの隔離方式

#432 の夜間ランナー (`claude -p` を launchd から無人で起動する) を、日常の macOS
ユーザーの資格情報から隔離する方式の決定 (#546)。無人用の設定ファイル・権限モード・
turn と時間の上限は #432 の決定事項が正本で、ここでは扱わない。

## 決定

**`claude -p` のプロセスを丸ごと sandbox-runtime (`srt`) で囲み、同じ macOS ユーザーで動かす。**
`~` を丸ごと `denyRead` で塞ぎ、ランナーに要るパスだけを `allowRead` で開ける。資格情報は、
ランナー専用のものを環境変数で渡す。作業場所は、issue ごとに GitHub から取る使い捨ての clone にする。

- 公式は、権限の確認を外した無人実行を「container / VM / sandbox runtime」の中で動かすよう
  書いている (<https://code.claude.com/docs/en/sandbox-environments>)。この決定はその 3 つのうちの 1 つ
- Claude Code の組み込み sandbox は Bash 経路しか囲まない (実測は [ai-operations.md §10](ai-operations.md#denyread-の実測--glob-は効くが削除リネームまで止まる))。
  `srt` は親の `claude` ごと囲むので、hook や MCP のように claude が起動する子プロセスも中に入る (推定。
  hook の発火は見たが、hook から外へ届かないことは測っていない)
- 無人用の設定では、組み込み sandbox を切る (`srt` の中では Seatbelt を重ねて張れない)

## 選ばなかった方式

| 方式 | 選ばなかった理由 |
|---|---|
| 別の macOS ユーザー | Keychain は OS のレベルで分かれる。一方、この home は `drwxr-x---` で group が `staff` (2026-11-20 実測) なので、別ユーザーを `staff` に入れると `~/development` (755) が読めてしまう。home を 700 にする、ランナー用に dotfiles と各 repo を別に clone する、LaunchDaemon (`UserName` 指定、sudo で配置) に変える、の 3 つが要り、#432 の「LaunchAgent を `link.sh` で配線する」と食い違う。公式の推奨資料には載っていない |
| devcontainer / コンテナ | 対象 repo ごとに toolchain の image が要り、Docker を常に動かすことになる。dotfiles の hook を Linux で動かすことにもなる。公式は、コンテナの中の `~/.claude` の資格情報も持ち出されうると警告している (<https://code.claude.com/docs/en/devcontainer>) |
| macOS VM | 隔離はいちばん強い。ただ、直列の夜間 1 本に対して構築と保守が重い |

## 作業場所: 使い捨ての clone (2026-11-26 決定)

本体のチェックアウトから切る worktree は使わない。worktree の commit は本体の `.git` (objects / refs)
に書くので、`allowWrite` に本体の `.git` を入れることになる (推定)。そこを開けたまま何も塞がないと
`.git/config` と `.git/hooks` を書き換えられ (下の実測)、user が普段 git を打つときに `srt` の外で動く。
`denyWrite` で 2 つを塞ぐ手もあるが、塞ぐ場所の列挙には漏れの実例がある。Cursor の
sandbox は `.git/config` を塞いでいたが、`git init --separate-git-dir` で作った別名の git ディレクトリから
`core.fsmonitor` を外で実行された
(<https://www.pillar.security/blog/git-directories-do-not-have-to-be-called-git>)。
clone なら、本体の `.git` を `allowWrite` に入れずに済む。

Docker は、agent の git 操作とホストの repo を強く分けたいときに clone モードを使うよう書いている
(<https://docs.docker.com/ai/sandboxes/security/workspace/>)。一方、worktree を使い
`.git/config`・`.git/hooks`・`.git/info` などを読み取り専用にする実装 (Sandcastle) もあり、worktree が
成り立たないわけではない。

clone にしても、上の手口は clone の中では防げない。外で動かさないために次を守る。

- clone は GitHub から取る。手元のパスからの clone は objects を hardlink で本体と共有し、`--shared` と
  `--reference` は本体の objects を参照する (<https://git-scm.com/docs/git-clone>)
- `srt` の外では、clone の中で git を打たない。`gh` も clone の外から `--repo` を付けて呼ぶ
  (`--repo` が無いと、`gh` は手元の git remote から repo を決める)。PR の特定は `gh`、後始末は clone の削除だけにする
- 失敗した clone を user が調べるときも、ログとファイルだけを見る。shell で中へ `cd` すると、プロンプトが
  git の状態を読みに行く (推測)

## 前提の実測 (2026-11-20、`@anthropic-ai/sandbox-runtime@0.0.83`)

`srt` の README には、macOS の Keychain を遮断するかどうかの記載が無い。組み込み sandbox の中では
`gh auth status` が失敗する ([ai-operations.md §10](ai-operations.md#sandbox-の-excludedcommands-が一次防御を丸ごと外す経路))
が、`srt` も同じとは限らないので、実装の前に確かめた。

| 設定の `denyRead` | 実行したもの | 結果 |
|---|---|---|
| (`srt` の外、対照) | `security find-generic-password -s gh:github.com` | exit 0 (`gh` の token は Keychain にある) |
| `~/.ssh` | 同上 | **exit 0 (届く)** |
| `~/.ssh` | `ls ~/.ssh` | `Operation not permitted`、exit 1 (設定は読まれている) |
| `~/.ssh`, `~/Library/Keychains` | `security find-generic-password -s gh:github.com` | `The specified item could not be found in the keychain.`、exit 44 |
| `~/.ssh`, `~/Library/Keychains` | `gh auth token` | exit 1 |
| `~` (`allowRead` に dotfiles のチェックアウトだけ) | `security find-generic-password -s gh:github.com` / `ls ~/.ssh` / `ls ~/development/articles` / `ls <dotfiles>` | 44 (`could not be found`) / `Operation not permitted` / `Operation not permitted` / exit 0 (`allowRead` は効いている) |

`srt` は、Keychain をファイル (`~/Library/Keychains`) の読み取りとして塞ぐ。そのため、`denyRead` が
`~/Library/Keychains` を覆っていることが、この方式の前提になる。`~` を丸ごと塞ぐ形でも覆えることは、
最後の行で確かめた。home の外 (`/Library/Keychains` など) は `~` では覆えないので、別に確かめる。
claude 自身の認証も Keychain からは読めなくなる (推定) ので、「資格情報」の節の環境変数で渡す。

## `claude -p` の実測 (2026-11-26、`srt` 0.0.83、Claude Code 2.1.326、macOS 26.6.2)

user のシェルから、使い捨ての repo と bare remote を相手に `srt` の中で `claude -p` を 1 回起動した。
設定は `denyRead` が `~`、`allowRead` が dotfiles のチェックアウトと `~/.local/share/claude`、`allowWrite` が
作業 dir 1 つ、`allowedDomains` が `api.anthropic.com` だけ。認証は `CLAUDE_CODE_OAUTH_TOKEN`、モデルは
Sonnet、`--permission-mode dontAsk --permission-prompts none`、組み込み sandbox は無効。7 turn、約 11 秒の
短い実行で、GitHub・PAT・launchd・`/dev` は通していない。

| 確かめたこと | 結果 |
|---|---|
| 隔離 | 「前提の実測」の最後の行と同じ結果。`gh auth token` は 1、対照の作業 dir と hook の `ls` は 0 |
| 通信先 | `api.anthropic.com` へは届き、`example.com` は proxy が 403 |
| 認証 | 完走 (`is_error: false`)。OAuth 用のドメインは許可していない。長時間の実行は未確認 |
| hook | SessionStart・PreToolUse・Stop が発火。`block-dangerous-commands.sh` は直接呼んで exit 2 (通常コマンドは 0) |
| skill と git | `CLAUDE_CONFIG_DIR` の skill が動き、Write・ブランチ作成・commit・push が remote に届いた |
| 無人での拒否 | allow に無い `touch` は拒否され (`permission_denials` に記録)、ファイルも無い |
| 組み込み sandbox | `srt` の中の `sandbox-exec` は `sandbox_apply: Operation not permitted`、exit 71 |
| worktree から本体の `.git` (`denyWrite` 無し) | `config` と `hooks` に書けた。README はどちらも書き込みの禁止に含めるが、この配置では効かなかった (理由は未確認) |
| 同上 (`denyWrite` に `config` と `hooks`) | どちらも `Operation not permitted`。ブランチ作成・commit・push は 0 |
| token の残り | 実行後の作業 dir と設定 dir に token の文字列は無い |

## 資格情報

`srt` の外で動く起動スクリプト (#432 の `scripts/night-run.sh`) が資格情報を読み出し、環境変数で
`srt` の中へ渡す。中の agent からは、その値も読める (起動後のプロセスが持つ環境変数を剥がせない
ことは [ai-operations.md §10](ai-operations.md#sandbox-の外側の-credential-保護--scrub-は入れない298))。
だから中に渡すのは、漏れても被害がランナーの範囲に収まるものだけにする。

| 用途 | 渡すもの | 置き場 (`srt` の外) |
|---|---|---|
| claude の認証 | `claude setup-token` で発行した `CLAUDE_CODE_OAUTH_TOKEN` | 未定 (#559)。候補は user の login keychain |
| GitHub | 対象 repo だけに絞った fine-grained PAT を `GH_TOKEN` に入れる。権限は Contents・Pull requests・Issues の write (ラベルとコメントに Issues が要る) | 同上 |

- login keychain に置くと、対話セッションの agent からも `security` で読まれうる (推定)。組み込み sandbox を
  有効にした対話セッションの Bash で、`security find-generic-password -s gh:github.com` が exit 0 になった
  (2026-11-25、存在の確認だけで値は読んでいない)
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

- `denyRead` は `~` を丸ごと塞ぐ。`allowRead` では、clone の置き場・`~/.claude-night`・`~/.local/share/claude`
  (claude の本体)・dotfiles のチェックアウト (共有する skill / hook / rules / agents の symlink 先) だけを開ける。
  `~/.claude` は日常のセッションの記録を含むので開けない (実測の構成は開けずに動いた)。
  `allowRead` は `denyRead` に優先する (README) ので、`~/Library/Keychains` や `~/.ssh` を含む親
  (`~` や `~/Library`) は書かず、葉に近いパスだけを書く
- `allowWrite` は、clone の置き場・`~/.claude-night`・その実行専用の一時ディレクトリ (`CLAUDE_CODE_TMPDIR` で渡す)。
  `/private/tmp` は日常のセッションの作業ファイルがあるので丸ごとは開けない。本体のチェックアウトと dotfiles は
  入れないので、本体の `.git` と、共有する hook / skill の実体には書けない
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
   になり、clone の置き場の `ls` は成功すること (後者は `allowRead` が効いていることの対照)
5. `srt` の中で、`GH_TOKEN` を入れた `gh api user --jq .login` が成功し、`gh repo view <対象外の repo>`
   は拒否されること (token の repo が絞れていることの確認)

1〜4 に当たる確認は「前提の実測」と「`claude -p` の実測」で通した (どちらもランナーの実際の設定ではない)。
ランナーの実際の `allowRead` での 1〜4 と、5 はまだ通していない。

## #432 に委ねる事項 (子 issue は #558〜#561)

- 起動の形: LaunchAgent (#432 の決定のまま) → `scripts/night-run.sh` (`srt` の外で、資格情報の読み出し・
  選定・ラベル操作・clone の作成と削除) → issue ごとに `srt --settings <ランナー用の設定> claude -p ...`。
  `srt` の設定ファイルは `claude-night/` に置く
- `srt` の版の固定と、その宣言の置き場。`srt` は beta で、設定形式は変わりうる (README)
- repo 固有のレジストリを許可する置き場
- hook は `srt` の中で動くので、sandbox の外へ出ることを前提にした
  hook (`excludedCommands` の `gh *` を当てにするものなど) は、中では日常の認証を持たない。その扱い

## 見直す条件

- `srt` の版を上げたとき: 「実機の確認手順」の 1〜3 を打ち直す
- clone と依存の取得が夜の処理を圧迫したとき: worktree と `denyWrite` の形を再評価する
- ランナーが merge まで進めた、または `GH_TOKEN` の範囲外へ書き込んだ事故があったとき: 権限で塞ぐ
  形へ移る。候補は次の 2 つで、どちらも未確認
  - GitHub App に required approvals を組み合わせる。PR の作者は自分の PR を approve できない
    (<https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/approving-a-pull-request-with-required-reviews>)
    ので、user が自分の PR を merge するには user を bypass に入れることになり、日常の merge の流れが変わる
  - push を repo 単位の deploy key に、`GH_TOKEN` を Contents read に分ける
- 夜間に並列で動かす (#511) とき、または対象 repo の信頼度が下がる (第三者の issue を
  `agent-ready` にする) とき: VM を再評価する
