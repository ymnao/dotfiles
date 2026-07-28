---
paths:
  - "**/*.sh"
  - "**/*.bash"
---

# Shell スクリプト規約

- **bash 3.2 互換で書く**(macOS 標準)。連想配列(`declare -A`)、
  `${var,,}` / `${var^^}`、`readarray` は使わない。小文字化は
  `tr '[:upper:]' '[:lower:]'` を使う
- **BSD / GNU 両対応で書く**。`sed -i` は使わない(引数仕様が非互換)。
  `grep -P` は使わない(`-E` を使う)。`date -d` / `stat -c` 等の
  GNU 拡張を避ける
- 新規スクリプトは `set -euo pipefail` から始める。exit code を自分で
  扱うスクリプトは `set -uo pipefail` にして理由をコメントに書く
- 変数展開は常に quote する(`"$var"`)。word splitting に依存しない
- **日本語などの多バイト文字が直後に続く変数展開は必ず `${VAR}` とブレースで
  囲む**。bash 3.2 + UTF-8 ロケールでは多バイト文字の一部バイトが変数名に
  取り込まれ、未定義変数として誤パースされる(`set -u` だと即死)
- **ロケール依存のあるテスト・スクリプトはロケールを明示 pin し、理由コメントを
  書く**(ambient ロケール頼みにしない)。バイト同一性を検査する箇所(BSD awk
  の `==`、日本語文字列比較、sort 順依存等)は `LC_ALL=C` 固定、逆に「UTF-8
  ロケール下での挙動」を回帰検査したい箇所は `LC_ALL=en_US.UTF-8` 等を明示
  pin する。pin の粒度は次のどちらでもよい:
  (a) shebang 直下で `export LC_ALL=...` — スクリプト全体が同じロケールに
      依存する場合 (実例: `tests/agents-md-sync/run-agents-md-sync-check.sh`)
  (b) ケース単位で `LC_ALL=... command args` 形式で行スコープ pin — 特定
      ケースだけ非デフォルトロケールを検査したい場合 (実例:
      `tests/verify-ci/run-verify-ci-tests.sh` の `stderr-defer-policy-utf8`
      ケース = `LC_ALL=en_US.UTF-8`)。
  CI は `make test` を LC_ALL matrix で 3 ロケール並列に回すため、pin 忘れは
  多くの場合 matrix job のどれかで fail する(issue #181)。ただし matrix の
  自動検出は「テストのアサーションが結果差を assert する」ケースに限る:
  silent に間違った値を返してもテスト側が拾わないパス、あるいは matrix に
  含まれない特殊ロケール(`ja_JP.SJIS` 等)固有の依存は matrix でも素通しに
  なるため、規約としての pin は依然必要
- 変更後は shellcheck(`-S warning`)を通す。警告はコードを直して解消し、
  disable コメントは追加しない
- **テストの floor / guard は「守る対象」から導出しない**。「必須ケースが
  実行されたか」を検査する下限値やガードは、検査対象そのもの(ケース一覧の
  配列長、対象ツールの数等)から計算すると、対象が減ったときに下限も一緒に
  下がって検出が無効化される。期待値は独立した定数として持ち、対象と食い違ったら
  fail させる。あわせて 2 点:
  - 数えるのは pass 数ではなく **実行数**(pass + fail)。pass を見ると
    「実行されたが FAIL した」を「実行されていない」と誤って報告する
  - **任意ケース(host 条件で skip されるもの)の分は差し引く**。含めると、
    任意ケースが走る環境では必須ケースの欠落が埋められて素通りする
  実例: `tests/fish-version-managers/run-fish-version-managers-tests.sh` の
  `EXPECTED_TOOLS` / `MANDATORY_PER_TOOL` / `optional_ran`(PR #224。当初は
  `${#TOOLS[@]} * 5` と対象から導出しており、上記 3 経路すべてで素通りしていた)
- **mutation check は 1 回に 1 変数だけ変える**。複数変えた mutant が FAIL しても
  どの変数が検出されたのか特定できず、誤った因果をコメントに残す。
  実例: issue #218 の対応で `fish_add_path -g` を `--path -a` に変えた mutant
  (スコープと append 性の 2 変数) が FAIL したことから「`-g` が PATH 順序を
  決めている」と結論づけたが、`--path` 単体でも順序は変わらず、実際に順序を
  決めていたのは config.fish の実行順だった(`-g` の役割は universal 化の回避)
- **コメントに書く「外部環境の事実」は、書く前に実測して測定日を添える**。
  runner イメージの pre-install 内容、ダウンロード先ドメイン、成果物サイズ、
  `bash` / `awk` の解決先、CLI オプションが実際に拾うエラー種別などは、
  もっともらしく書けてしまう上に**設計判断の根拠として引用される**ため、
  外れると判断ごと腐る。「〜なので依存は増えない」「〜MB なのでキャッシュ不要」
  のような**根拠つきの断定**を書くときは、その根拠を必ず 1 回測る
  (`curl -sI` の Location、`ls -l` のバイト数、runner-images の README、
  `man` の該当項)。測定日を添えるのは、後から読む人が「いつの事実か」を
  判断できるようにするため。
  実例: issue #196 の対応で 1 PR のうちに 4 件外した — release asset は
  `release-assets.githubusercontent.com` へリダイレクトされるのに「失敗
  ドメインは増えない」、tarball は 2.4MiB なのに「~1.5MB」、`bash <path>`
  起動では shebang が参照されないのに「shebang 側で決まる」、
  `--retry-connrefused` は ECONNREFUSED だけなのに「DNS 失敗も再試行される」。
  いずれもレビュアーが実測して覆した(2 周連続)
- **`mktemp -d` はテンプレートを明示する** (`mktemp -d "${TMPDIR:-/tmp}/<name>.XXXXXX"`)。
  macOS の BSD mktemp はテンプレート無しだと **TMPDIR を無視**して
  `confstr(_CS_DARWIN_USER_TEMP_DIR)` の per-user temp dir
  (`/var/folders/.../T`) を使うため、TMPDIR を差し替えた環境では作業先が
  意図とずれる。GNU coreutils は TMPDIR を見るので、**macOS でだけ**
  「TMPDIR を設定したのに効かない」形で出る。
  実例: issue #196 の対応中、sandbox 下で `TMPDIR` を書き込み可能な場所に
  差し替えて手元検証したところ `mkdtemp failed on /var/folders/...:
  Operation not permitted` で落ちた (スクリプト側のバグではなく mktemp の
  仕様差)。テンプレートを明示すると BSD / GNU どちらでも TMPDIR に従う
- **一時ディレクトリのパスを「外部ツールが返す値」と文字列比較するテストでは、
  `${TMPDIR:-/tmp}` を連結する前に末尾スラッシュを落とす**。macOS の TMPDIR は
  末尾がスラッシュ(`getconf DARWIN_USER_TEMP_DIR` → `/var/folders/.../T/`)
  なので、そのまま連結すると WORKDIR に `//` が入る。一方で比較の相手側は
  `//` を潰した値を返すことが多く(fish の `fish_add_path` は
  `builtin realpath -s`、`scripts/link.sh` は `cd` + `pwd`)、生パスとの比較
  だけが一致しなくなる。TMPDIR に末尾スラッシュが付く環境でのみ落ちるため
  **flaky に見えるが実際は決定的**で、原因に辿り着くのが高い。
  剥がした後も `//` が残る場合(`TMPDIR=/a//b`)は、一部ケースが無言で落ちる
  代わりに原因つきで即死させるガードを置く。
  適用条件は「**比較する**」場合に限る — 一時ディレクトリを作って使うだけで
  正規化前後のパスを突き合わせないテストは対象外(repo 内の `${TMPDIR:-/tmp}`
  利用約 18 箇所のうち、実測で末尾スラッシュ有無に結果が依存したのは下記
  3 箇所だけだった)。
  実例: issue #225 / `tests/fish-pnpm/`・`tests/fish-version-managers/`・
  `tests/link/`(前 2 者は fish の `$fish_user_paths` と、後者は `readlink` が
  返す symlink target と比較していた)
- **テスト用の一時 git リポジトリを作ったら、`git init` の直後に
  `git config gc.auto 0` と `git config maintenance.auto false` を置く**。
  `git commit` は auto gc を detach して起動するため、これがテスト終了時の
  `trap` の `rm -rf` と競合し、`.git/objects/info/packs` と `.git/info/refs` を
  書き戻す。結果として **全ケースが pass していても `rm` が ENOTEMPTY で失敗し、
  スイートが exit 1 になる**。commit 数が増えるほど発生確率が上がり、症状が
  「たまに落ちる」なので flaky と誤診しやすい(実測: 無効化前は 20 回中 2 回、
  無効化後は 30 回連続 green)。
  現在 repo 内で一時 git リポジトリを作るのは
  `tests/classify-risk/run-classify-risk-tests.sh` の 1 箇所だけなので、
  これは**新しくその形のテストを書くとき向けの規約**。
