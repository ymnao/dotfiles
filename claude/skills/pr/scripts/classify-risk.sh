#!/usr/bin/env bash
set -euo pipefail

# 現在のブランチの diff (base...HEAD) をリスク分類する。
#
# 使い方: classify-risk.sh <base-branch>
# 出力 (JSON): {"tier": "high|medium|low", "reasons": ["<rule>: <対象>", ...]}
# exit: 0 = 分類成功 (tier がどれでも 0) / 1 = 前提エラー
#
# 分類はモデルの判断に任せず path/grep で決定的に行う (下位モデルでも
# 同一精度にするため)。**high 方向のルール**追加はこのファイルの RULES
# セクションだけを編集すればよい構造にしてある。
# 一方 tier の別方向の操作 (medium 床など) は check_path / check_content /
# check_deleted の 3 プリミティブでは表現できない — いずれも `$reasons` に
# 積んで high に固定する片方向の装置なので、RULES ではなく下の tier 確定
# ロジックを直接編集することになる (issue #255 の床が実例)

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is not installed" >&2
  exit 1
fi

BASE="${1:-}"
if [ -z "$BASE" ]; then
  echo "usage: classify-risk.sh <base-branch>" >&2
  exit 1
fi

# base ref 解決 (gather-branch-info.sh と同じ流儀: ローカル優先、origin/ フォールバック)
REF="$BASE"
if ! git rev-parse --verify "$BASE" >/dev/null 2>&1; then
  if git rev-parse --verify "origin/$BASE" >/dev/null 2>&1; then
    REF="origin/$BASE"
  else
    echo "ERROR: base branch '$BASE' not found locally or on origin" >&2
    exit 1
  fi
fi

# 全 file list (path check / tier=low 判定用)。改行含みパスは quote されうるが
# path rule は行単位 grep なので実害なし。--name-only の quote は名前表示問題
# だけで、実 pathspec を必要とするのは下の code_files 経路のみ
files=$(git diff "$REF...HEAD" --name-only)

# content check の除外対象: 「エージェントに指示として解釈されない」文書のみ。
# `README*.md` / `docs/` / `LICENSE*` / `.txt` / `evals/*.md` fixture。
# SKILL.md / AGENTS.md / CLAUDE.md / claude/skills/**/*.md などは
# エージェントが指示として解釈するため content check の対象に残す
# (security ゲート bypass 防止 / eval fixture 誤検知回避の両立)。
# 散文の誤検知は「ここから *.md を除外する」ではなく RULES 側のパターンを
# 実行構文に寄せて直すこと (issue #227)
NOT_EXECUTABLE_DOC_PATTERN='(^|/)README[^/]*\.md$|^docs/|(^|/)LICENSE[^/]*$|\.txt$|(^|/)evals?/[^/]*\.md$'

# code_files を pathspec 安全に取得するため -z (NUL 区切り) を使う。
# 空白・改行・非 ASCII を含むパスでも正しく pathspec 復元できる
added_code=""
paths=()
while IFS= read -r -d '' f; do
  [ -n "$f" ] || continue
  # NOT_EXECUTABLE_DOC_PATTERN にマッチするファイルは content check 対象外
  if ! printf '%s' "$f" | grep -qE "$NOT_EXECUTABLE_DOC_PATTERN"; then
    paths+=("$f")
  fi
done < <(git diff "$REF...HEAD" --name-only -z)

if [ "${#paths[@]}" -gt 0 ]; then
  # 追加行 (+++ ヘッダを除く)。バイナリ diff は git が行を出さないので無視される。
  # --literal-pathspecs で diff 由来のパスに紛れ込みうる pathspec magic
  # (`:(exclude)...` 等) を無効化し、別ファイルの content check を skip
  # させる bypass を防ぐ
  added_code=$(git --literal-pathspecs diff "$REF...HEAD" --unified=0 -- "${paths[@]}" 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' || true)
fi
# 削除されたファイル (rename は R として別扱いになるため含まれない)
deleted=$(git diff "$REF...HEAD" --name-only --diff-filter=D)

reasons=""
add_reason() {
  reasons="${reasons}${reasons:+
}$1"
}

# パスルール: 変更ファイル名が ERE にマッチしたら HIGH
check_path() {
  local rule="$1" pattern="$2" m
  m=$(printf '%s\n' "$files" | grep -iE "$pattern" | head -3 || true)
  [ -n "$m" ] && add_reason "$rule: $(printf '%s' "$m" | tr '\n' ' ')"
  return 0
}

# 内容ルール: doc-only を除くコード側ファイルの追加行が ERE にマッチしたら HIGH
check_content() {
  local rule="$1" pattern="$2" m
  m=$(printf '%s\n' "$added_code" | grep -iE "$pattern" | head -2 || true)
  [ -n "$m" ] && add_reason "$rule: $(printf '%s' "$m" | cut -c1-80 | tr '\n' ' ')"
  return 0
}

# 削除ルール: 削除されたファイル名が ERE にマッチしたら HIGH
# (エージェントが「テストを消して green にする」事故の検出。変更・追加は対象外)
check_deleted() {
  local rule="$1" pattern="$2" m
  m=$(printf '%s\n' "$deleted" | grep -iE "$pattern" | head -3 || true)
  [ -n "$m" ] && add_reason "$rule (deleted): $(printf '%s' "$m" | tr '\n' ' ')"
  return 0
}

# ---- RULES (ここだけ編集すればルールを増減できる) ----
check_path "auth-code"    '(^|/)(auth|login|session|oauth|token|secret|password|crypt|credential)[^/]*(/|$)'
check_path "ci-config"    '^\.github/workflows/|^\.github/scripts/|Jenkinsfile|\.gitlab-ci|^\.circleci/'
check_path "dependency"   'package\.json$|package-lock\.json$|pnpm-lock\.yaml$|yarn\.lock$|bun\.lockb?$|pyproject\.toml$|uv\.lock$|poetry\.lock$|requirements[^/]*\.txt$|go\.(mod|sum)$|Cargo\.(toml|lock)$|Gemfile(\.lock)?$|Brewfile$'
check_path "agent-config" 'settings[^/]*\.json$|(^|/)hooks/|hooks\.json$|AGENTS\.md$|CLAUDE\.md$|\.mcp\.json$'
check_path "env-files"    '(^|/)\.env|\.npmrc$|config\.toml$'
check_path "infra"        'Dockerfile|docker-compose|\.tf$|\.tfvars$'
# exec-pattern の `eval` は、シェルの実行構文として読める形だけを検出する
# (issue #227)。散文中の「eval」の語では発火させないが、実行形を取りこぼすと
# `.md` 単独 diff は tier=low = 無レビューになるため、FN は FP より高くつく。
# 5 経路の OR で、どれか 1 つでも当たれば検出する:
#   ADJACENT — eval から展開・引用文字までが、シェルの語として解釈できる
#     ASCII トークンだけで繋がっている形。`run: eval "$x"` のように行の途中に
#     前置がある実行指示形を拾うのが役割 (位置に依存しない)
#   CMDPOS — eval がシェルのコマンド位置 (行頭 / `;` `&` `{` `!` `||` の直後 /
#     `then` `do` `else` `elif` の直後) にあり、
#     同じ行のどこかに展開・引用文字がある形。ADJACENT の語クラスは allow-list
#     なので `[` `\` `>` `,` や多バイトを 1 文字挟むだけで越えられる
#     (`eval arr[$i]=$X` `eval value=\$$name` `eval 2>/dev/null "$x"`)。
#     位置を固定する代わりに間の文字種を問わないことでその穴を塞ぐ
#   OPENPOS — `(` または単独の `|` の直後に eval があり、**eval の次のトークンの
#     先頭が ASCII のシェル語文字**で、同じ行に展開・引用文字がある形
#     (`(eval arr[$i]=$X)` `producer | eval arr[$i]=$X`)。この 2 文字は
#     日本語の丸括弧 (`(eval が ...`) と Markdown のテーブル行
#     (`| eval | ... |`) と衝突するので CMDPOS の位置集合には入れられないが、
#     「次トークンが ASCII で始まる」条件を足せば散文と分離できる
#     (散文では eval の次が多バイト、テーブルでは次が `|` になる)
#   LINECONT — 行末が `eval \` の形。引数が次行にあるため grep の行単位
#     マッチでは中身を見られないので、この形自体を検出対象にする。
#     eval の左側に語境界を要求する (`preeval \` `re-eval \` を弾くため)
#   BACKTICK — バッククォートのコマンド置換の中の eval
#     (`` x=`eval arr[$i]=$X` ``)。位置集合 (CMDPOS / OPENPOS) にバッククォートを
#     足す形では塞げない。真因は**`EVAL_Q` 自身がバッククォートを含む**ことで、
#     `.*${EVAL_Q}` の条件が「行内のどこかにバッククォートがある」だけで自明に
#     充足される。Markdown のインラインコード行は必ず閉じバッククォートを持つ
#     ので、位置集合に足すと散文 (`` `eval ls -la` は静的リテラルの例 ``) が
#     無条件に発火する。そこで独立経路にして 2 点を要求する:
#       (a) 展開・引用文字の集合から backquote を除く (EVAL_QNB)
#       (b) `[^`]*` で、**閉じバッククォートに達する前に**その文字が現れること
#     これで「バッククォート区間の中で展開が起きている」形だけを取れる。
#     区間の外に `$` があるだけの散文 (`` `eval ls -la` を $HOME で実行 ``) は
#     発火しない (issue #230)
# 他経路が拾うので FN にならないもの (BACKTICK 単独では当たらない):
#   `` `eval "$x"` `` — eval の次が `"` で先頭文字クラスに入らないが ADJACENT。
#   `` x=$(eval arr[$i]=$X) `` — OPENPOS の `(` 分岐。
# 既知の非検出 (実測で low を確認済み。**塞げていない形をここに漏らさない** —
# この節は次に触る人が「もう閉じた」と判断する根拠になるので、他経路が拾う形
# だけを並べると非対称な安心を与える):
#   `` x=`eval \`build_cmd\`` `` — 入れ子バッククォートで内側が escape された形。
#     `[^`]*` が閉じ ` の前に展開文字を要求するので当たらない。区間内に
#     バッククォートを許すと散文が丸ごと巻き込まれるため、意図的に取らない
#   `` x=`eval >$LOG $CMD` `` `` x=`eval {a,b}$X` `` `` x=`eval ~/$X` ``
#     `` x=`eval ((i=$X))` `` `` x=`eval *$X` `` — 第 1 引数が
#     `>` `{` `~` `(` `*` で始まる形。EVAL_WORD_BT は allow-list なので
#     入っていない。`"` `'` `$` 始まりは ADJACENT が拾うが、これらは
#     どの経路も拾わない。**先頭文字クラスを広げれば個別には塞げるが、
#     その足し方こそ下の trigger が止めようとしているもの**なので広げない
#   `- eval arr[$i]=$X` / `run: eval arr[$i]=$X` — **行頭以外**に置かれた実行形。
#     Markdown の箇条書き接頭辞 2 文字で CMDPOS の位置集合 (`^\+`) を外せる。
#     BACKTICK 由来ではなく #227 以前からの穴で、バッククォート形より広い。
#     経路追加では届かないので下の一般化 trigger が発火した (経緯と対応は
#     LOW_ONLY_PATTERN 直後の medium 床のコメントに 1 箇所だけ書いてある)。
#     **この形はいまも high にはならない** — 床で最低 1 観点のレビューに
#     載るだけなので、非検出の一覧からは外さない
#   展開も引用も一切含まない静的リテラルの `eval ls -la`
# (動的展開が無く、このルールが見ているリスクに当たらないため意図的)。
# 実測 (2026-08-02。測定方法を明記する — 方法が書いてないと別の数え方で
# 再現できず「どちらが正しいか」で往復する。**`git ls-files` の各ファイルを
# symlink 追従で読み、全行に `+` を前置して `grep -iE` し、マッチした
# ファイル数を数える**。`git grep` は blob を見るので symlink 配下
# (`claude/hooks/*` 等) が当たらず、同じ総数でも内訳が変わる):
# ADJACENT のみ = 8 / 4 経路 = 10 / BACKTICK を足した 5 経路 = 10。
# **旧 `eval ` の側は数値を載せない** — 走査方法の差 (symlink 追従の有無) で
# 57 と 62 のどちらにも振れ、レビューで 3 回とも違う値が出て決着しなかった。
# 絶対値は測り方に敏感すぎて根拠にならないので、**同一時点・同一方法で取った
# 4 経路と 5 経路の差**だけを判断に使う (この 3 つは方法を問わず再現した)。
# **この増分 0 が測っているのは FP 面積であって経路の有効性ではない** —
# コーパスは repo 自身の既存ファイルで、脅威は「これから来る diff」の側に
# あるため (有効性は下の検体と mutation check の側で見る)。
# **さらに「ファイル数の増分 0」を「散文への巻き込みが無い」と読んではいけない** —
# 0 なのはそのファイルが既に他経路でマッチ済みだからで、行粒度では
# 4 経路 41 行 -> 5 経路 53 行 (+12) 増えている (増分のうち 4 行はこの
# ファイル自身の解説散文)。巻き込みは実際にあり、向きが low->high =
# レビューが増える側なので許容している、が正しい読み。
# 手で組んだ検体では危険形 24 種を 24 件とも検出、散文 11 種は 0 件検出。
# 5 経路それぞれの検出責務は mutation check で確認済み (経路を 1 つ落とすと
# tests/classify-risk の対応ケースが FAIL する)。
# 経路を足し続けることの限界 (issue #230 が提起した論点):
#   行単位の grep は、コードフェンスの内外も行をまたぐ構文も見られないので、
#   散文と実行構文を原理的に分離しきれない。取りこぼしは #227 から数えて
#   ラウンドを跨いで出続けている。経路追加は暫定であって恒久策ではない。
#   より深い代替は #230 に 2 案ある (`.md` はコードフェンス内の行だけを
#   content check する / `.md` で発火したら medium に落とす重み付け)。
#   **次のいずれかを観測したら経路追加をやめて上の一般化に切り替える**
#   (毎回その場で判断すると必ず「今回はあと 1 本」に倒れるため先に書く):
#     - 経路が 6 本目に達する
#     - 同一 issue の中で 2 ラウンド以上の経路追加往復が発生する
#     - **経路追加では届かない FN を観測する** (上の「行頭以外の実行形」型)。
#       本数や往復回数だけを trigger にすると、いま既に観測済みのこの穴を
#       見ても発火しない。停止条件は在庫ではなく FN 側でも測る
#   **3 つ目は #255 で発火済み**。ただし対応は上の 2 案の**どちらでもない**
#   (対応は LOW_ONLY_PATTERN 直後の medium 床)。2 案はどちらも未実装のまま:
#   コードフェンス案は床とは独立に検出精度を上げる余地として残っており、
#   重み付け案は「high で発火したものを medium に落とす」天井なので、
#   発火しない形が問題だった #255 には効かない。
#   **経路 6 本目の trigger は生きている** — 床があっても exec-pattern に
#   経路を足してよい理由にはならない
# なお下の例示コメント自身がこのパターンにマッチするため、このファイルを触る
# PR は tier=high になる。実行構文の具体例を残す方を優先した意図的な結果で、
# 自ファイル除外は入れない (除外は bypass 経路になる)。
# eval の引数の語として許す文字。EVAL_WORD と EVAL_WORD_BT の**両方**がこれを
# 使う。片方に文字を足してもう片方に足し忘れる drift を構造的に防ぐため、
# 集合の中身は 1 箇所 (CORE) にしか書かない。bracket 内で `-` が範囲指定に
# ならないよう、CORE には `-` を入れず各定義側で端に置く
EVAL_WORD_CORE='A-Za-z0-9_./='
EVAL_WORD="[-${EVAL_WORD_CORE}]"  # eval の引数の語として許す文字集合
EVAL_Q='["$`'"'"']'               # 展開・引用の開始文字 (" $ backquote ')
EVAL_ADJACENT="eval([[:space:]]+${EVAL_WORD}+)*[[:space:]]+(${EVAL_WORD}*[=_])?${EVAL_Q}"
EVAL_CMDPOS="(^\\+|[;&{!]|\\|\\||(^|[^A-Za-z0-9_])(then|do|else|elif)[[:space:]])[[:space:]]*eval[[:space:]].*${EVAL_Q}"
EVAL_OPENPOS="[(|][[:space:]]*eval[[:space:]]+${EVAL_WORD}.*${EVAL_Q}"
EVAL_LINECONT='(^|[^A-Za-z0-9_-])eval[[:space:]]*\\$'
# EVAL_BACKTICK の (a) に対応する集合。手書きの複製にせず EVAL_Q から
# backquote を除いて**導出する** — 別リテラルで持つと EVAL_Q に引用文字を
# 足したとき QNB 側が黙って追随せず、BACKTICK 経路だけが古い集合のまま
# 陳腐化する (テストは経路の入出力しか見ないのでこの drift は検出できない)
EVAL_QNB="${EVAL_Q//\`/}"
# BACKTICK の先頭 1 文字だけは EVAL_WORD より広い集合を使う。EVAL_WORD は
# allow-list なので `\` `[` `]` で始まる引数 (`` `eval \$name=$X` ``
# `` `eval [ -n $X ]` ``) が抜け、**この PR が閉じると宣言した族の中に
# bypass が残る**。CMDPOS の解説が危険形として挙げている `eval value=\$$name`
# と同じ「`\` を挟む」族 (ただし `value=` 始まりの原形は先頭が `v` なので
# EVAL_WORD でも当たる — 抜けるのは `\` が先頭に来る形)。
# 散文との分離は (a)(b) の 2 条件が担っている。このクラスの役割は
# **eval の次が語らしくない形を落とすこと**で、具体的には多バイト散文
# (`` `eval と "参照"` の違い ``) と ASCII 記号始まり (`>` `{` `~` `(` `*`) の
# 両方を落とす。後者は上の「既知の非検出」に挙げた FN の直接原因でもある
# (クラスは FP と FN のトレードオフの調整点であって、片側だけの装置ではない)。
# 広げた 3 文字については、危険形 5 種が high に転じ散文 6 種が low のまま
# であることを実測した (この検体の範囲では FP 増分 0。行粒度の全体傾向は
# 上の実測節を参照)
# EVAL_WORD + backslash + 角括弧。CORE を共有するので EVAL_WORD に文字を
# 足せば自動で追随する (`-` は範囲指定を避けるため末尾に置く)
EVAL_WORD_BT="[][\\\\${EVAL_WORD_CORE}-]"
EVAL_BACKTICK="\`[[:space:]]*eval[[:space:]]+${EVAL_WORD_BT}[^\`]*${EVAL_QNB}"
check_content "exec-pattern"        "${EVAL_ADJACENT}|${EVAL_CMDPOS}|${EVAL_OPENPOS}|${EVAL_LINECONT}|${EVAL_BACKTICK}|child_process|subprocess|os\\.system|exec\\(|dangerouslySetInnerHTML"
check_content "pipe-to-shell"       '(curl|wget)[^|;]*\|[[:space:]]*(ba|z|da)?sh'
check_content "permission-widening" 'chmod (777|666)|--dangerously|--no-verify'
check_deleted "test-removal" '(^|/)(tests?|__tests__|spec)/|\.(test|spec)\.[a-z]+$|_test\.(go|py|rb|ts|tsx|js|jsx)$|\.cases\.jsonl$'
# 全 diff がこのパターンにマッチする文書だけなら tier=low の候補になる。
# **#255 の medium 床が入った後は、これ単独では low を決めない** — 実際に
# low になるのは、さらに全ファイルが NOT_EXECUTABLE_DOC_PATTERN にも入る
# ときだけ (下の床を参照)。旧コメントは「危険文字列がない SKILL.md /
# CLAUDE.md の tweak も low 扱いにするため」と幅の広さを正当化していたが、
# SKILL.md は床で medium になり、CLAUDE.md は check_path "agent-config" で
# 以前から high なので、その理由はもう成立しない。
# 現状このパターンが単独で結果を変えるのは、NOT_EXECUTABLE に入って
# LOW_ONLY に入らない形 (非 root の `sub/LICENSE` 等) だけ
LOW_ONLY_PATTERN='\.md$|^docs/|^LICENSE|\.txt$'
# medium 床: エージェントが指示として解釈する文書を含む diff は low に
# 落とさない (issue #255)。**天井ではなく床**なので high 判定には影響しない。
#
# 上の exec-pattern が「実行構文だけを検出する」方向で 3 ラウンド (#227 /
# #230 / #255) 経路を足してきたが、行単位の grep はコードフェンスの内外も
# 行をまたぐ構文も見られないため、散文と実行構文を原理的に分離しきれない。
# 実際 `- eval arr[$i]=$X` は Markdown の箇条書き接頭辞 2 文字で CMDPOS の
# 位置集合を外れ、SKILL.md 単独 diff が tier=low = **無レビューで merge** に
# なる。exec-pattern の解説にある「経路追加では届かない FN を観測したら
# 一般化に切り替える」trigger がこれで発火した。
#
# そこで検出精度を上げる方向ではなく、**「無レビュー」という結果の側を消す**。
# 床なので、パターンが取りこぼしても最低 1 観点が走る — ただし**保証の強さは
# harness で違う**: Claude 側は `/pr` step 4 の medium が codex-review
# security を実際に走らせるが、codex 側の `/pr` は独立レビュー不可なので
# 「merge 前に Claude Code 側で回すこと」と PR 本文に記録するところまで。
# 取りこぼしを 0 にする必要が無くなる分、exec-pattern 側に経路を足し続ける
# 圧力も下がる。
#
# **床の除外集合は content check の除外集合 (NOT_EXECUTABLE_DOC_PATTERN) とは
# 別物**。当初は「同じ集合を 2 箇所に書くと drift する」という理由で後者を
# 再利用したが、レビュー (codex security / code-reviewer) が具体的な反例を
# 出して覆した。2 つの問いは別だから:
#   content check の除外 = 「この行を grep して実行構文を探す価値があるか」
#                          (散文を grep すると FP になるので docs/ を外す)
#   床の除外           = 「この文書はエージェントが指示として読むか」
#                          (読むなら、危険文字列が無くてもレビューに載せる)
# `docs/ai-operations.md` はこの 2 つで答えが割れる典型で、散文だが
# `agents/AGENTS.md` と `claude/skills/paper-review/SKILL.md` から参照され、
# §8 は settings.json の手動レビュー手順を命令形で書いている。集合を共有
# していた版では、この文書の変更が tier=low = 無レビューで通っていた。
# `evals/` 配下の `.md` も同様 (Setup / Prompt / Pass criteria を
# エージェントが手順として読んで実行する)。
#
# よって床は独自の除外パターンを持つ。含めるのは**エージェントが指示として
# 読まない**ものだけ: repo root の `README*.md` (人間向けの入口) と
# `LICENSE*`。drift は「集合を 1 つにする」ではなく、両パターンに触れるときの
# 判断基準を上に書き下すことで防ぐ。
#
# `.txt` を除外に入れない理由 (一度入れて codex-review security に覆された):
# この repo の `.txt` は散文ではなく**制御ファイル**で、
# `tests/integrity/allowed-mcp.txt` は `~/.claude.json` に存在してよい MCP
# サーバーの許可リスト、`packages/winget-packages.txt` /
# `packages/scoop-packages.txt` は `scripts/install.ps1` が読んで実際に
# パッケージを入れる manifest。**許可リストを広げる変更が無レビューで通る**
# のは、この床が消そうとしている結果そのもの。「エージェント指示文書ではない」
# は除外の理由にならない — 床が守るのは「実環境に効く変更を無レビューにしない」
# ことで、指示文書はその一例にすぎない。
#
# **既知の非検出 (床の外に残るもの。閉じたと読ませないために明記する)**:
#   - 非 root の `README*.md` (`sub/README.md`) — root の入口文書と同じ
#     パターンで除外される。`claude/skills/codex-review/evals/README.md` の
#     ように eval の実行手順を書いた README がこれに当たる
#
# rename 対策として床の入力だけは `--no-renames` で取り直す。`--name-only` は
# rename の**宛先しか返さない**ため、`git mv claude/skills/foo/SKILL.md
# docs/x.md` のように指示文書を床の外へ動かす変更が、元パスを分類器から
# 見えなくして low で通っていた (削除は `skill-md-removal-floor` で塞いで
# いたのに、同じ「指示文書が無くなる」変更である rename は素通りしていた)。
# `--no-renames` にすると rename が delete + add に分解され、元パスも入力に
# 入る。**`$files` 側は `--name-only` のまま**にする — check_deleted が
# `--diff-filter=D` で rename を意図的に除外しており、そちらの意味論を
# 変えないため。
#
# コスト: SKILL.md の些細な変更でも codex-review security が回る。この
# repo は skill 変更 PR が多いので実際にレビュー時間は増える。「無レビュー
# で通る経路を残さない」方を優先した意図的なトレードオフ
FLOOR_EXEMPT_PATTERN='^README[^/]*\.md$|(^|/)LICENSE[^/]*$'
# ---- /RULES ----

tier="medium"
if [ -n "$reasons" ]; then
  tier="high"
elif [ -n "$files" ] && [ -z "$(printf '%s\n' "$files" | grep -ivE "$LOW_ONLY_PATTERN" || true)" ]; then
  # doc-only diff。エージェント指示文書を含むなら medium 床で止める
  floor_docs=$(git diff "$REF...HEAD" --name-only --no-renames \
    | grep -vE "$FLOOR_EXEMPT_PATTERN" | head -3 || true)
  if [ -n "$floor_docs" ]; then
    tier="medium"
    add_reason "medium-floor: エージェント指示文書の変更を含むため無レビューにしない: $(printf '%s' "$floor_docs" | tr '\n' ' ')"
  else
    tier="low"
    add_reason "low-only: 変更がドキュメント類のみ"
  fi
fi

jq -n --arg tier "$tier" --arg reasons "$reasons" \
  '{tier: $tier, reasons: ($reasons | split("\n") | map(select(length > 0)))}'
