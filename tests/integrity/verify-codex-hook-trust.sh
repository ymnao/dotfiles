#!/usr/bin/env bash
set -uo pipefail

# codex hook の承認状態 (trusted_hash) を検査する warn-only 層
# (issue #239 でキー存在検査、issue #214 で hash 値検証を追加)。
#
# 背景: codex の hook は「定義を repo に置いて symlink する」だけでは動かない。
# 新しい entry は Untrusted 扱いになり、codex TUI で承認されて初めて
# ~/.codex/config.toml の
#   [hooks.state."<hooks.json の絶対パス>:<event>:<group>:<index>"]
#   trusted_hash = "sha256:..."
# に記録され、以降実行される。承認は host 側の user 操作で agent からは行えない。
#
# 問題: 配線済みだが未承認、という状態を検査する層がどこにも無かった。
# 監視・警告系の hook は「警告が出ない = 正常」と「そもそも動いていない」が
# 区別できないため、静かに無効化されたまま気付けない。新しいマシンに
# セットアップして承認を忘れた場合も同じ状態になる。
#
# 検査は 2 段:
#   1. codex/hooks.json (host からは ~/.codex/hooks.json) の各 hook entry に
#      対応する [hooks.state] キーが ~/.codex/config.toml にあるか (= 承認済みか)
#   2. そのキーの trusted_hash が、現在の hooks.json の定義から計算し直した
#      値と一致するか (= その承認が今の定義に対するものか)
#
# キー書式は codex-cli 0.146.0 の ~/.codex/config.toml から実測 (2026-07-31)。
#
# ---- trusted_hash の payload 仕様 (codex-cli 0.146.0 で実測、2026-08-03) ----
#
# codex は hook の**設定 identity だけ**をハッシュする (参照先スクリプト本体の
# 内容は含まない。詳細と帰結は docs/ai-operations.md §10)。payload は次の
# オブジェクトの canonical JSON (キーを再帰的にソート・compact・UTF-8 生出力・
# 末尾改行なし) で、その sha256 hex が "sha256:<hex>" として記録される:
#
#   event_name — hooks.json の event 名を snake_case 化 (PreToolUse → pre_tool_use)
#   matcher    — その group の matcher。**空文字列のときはキーごと省略される**
#   hooks      — 要素 1 個の配列 (group 全体ではなく、その index の hook だけ)
#     additionalContextLimit — hooks.json に無いときはキーごと省略 (**下記の注意**)
#     type            — 既定 "command"
#     command         — hooks.json のまま
#     async           — 既定 false
#     timeout         — **hooks.json に無いときの既定は 600**
#     statusMessage   — hooks.json に無いときはキーごと省略
#
# **additionalContextLimit だけは実測で裏が取れていない**。docs/ai-operations.md
# §10 の上流実装読解 (normalized_handler はこの 5 つの設定値から成る) に従って
# payload に含めているが、この機体の codex/hooks.json はどの hook でもこのキーを
# 使っておらず、記録済み hash 6 件はすべて「キーが無い = 省略」の側でしか
# 検証できていない。キーを実際に付けたときの挙動 (省略しないのが正しいか、
# 既定値付きで入るのか) は未確認。**外れた場合は当該 entry が MISMATCH に
# なるだけで、方向は fail-loud** (承認済みと誤報告する側には倒れない)。
# 実際に使うことになったら、承認後の記録値と突き合わせて確かめること。
#
# 根拠: この機体の ~/.codex/config.toml に記録済みの trusted_hash 6 件すべてを
# バイト一致で再現した (issue #214)。0.145.0 時点では 5/6 で、未再現だった
# Stop entry の原因が上記 2 つの既定・省略規則 (matcher 空の省略 / timeout 600)
# だった。canonical JSON の生成は jq の insertion order + tojson に依存する
# (下の JQ_ENTRIES はキーをソート順に構築している)。
#
# **これらは codex の実装詳細なので upgrade で変わりうる**。変わったときは
# MISMATCH として出る (見逃しではなく fail-loud) が、**「仕様が変わったら全 entry が
# MISMATCH になる」とは限らない** — 既定値や省略規則の変更は**その規則に依存する
# entry だけ**を外すため、部分不一致になる。実測: `($h.timeout // 600)` を
# `// 601` に変えた mutant は、この機体の 8 entry のうち timeout を持たない
# stop:0:0 の 1 件しか外さなかった (残り 7 件は timeout を明示している)。
#
# したがって MISMATCH の原因は 2 つあり、件数からは判別できない:
#   (a) 承認後に hooks.json の当該 entry を書き換えた → その hook は Untrusted に
#       戻っており実行されていない。codex TUI で再承認すれば直る
#   (b) codex の payload 仕様が変わった → docs/ai-operations.md §10 と本ヘッダの
#       再実測が必要
# **判別は「その entry の hooks.json を変更した覚えがあるか」で行う**。覚えが
# 無いなら (b) を疑い、**再承認する前に**再実測すること — 再承認すると codex が
# 新しい hash を書き戻し、仕様が変わったという唯一の証拠が消える。
#
# 検知時: **警告のみで exit 0**。承認も再承認も user 操作でしか行えず、agent が
# 直せないものでゲートを落としても手詰まりになるだけなため
# (issue #239 も block ではなく警告と指定している)。run-gate.sh は
# set -e で走るので、全経路で exit 0 することがこのスクリプトの契約。
#
# 環境変数 (テスト用):
#   INTEGRITY_HOME — $HOME の代わりに検査するルート
#
# ~/.codex が無い環境 (CI・codex 未セットアップ機) では skip (fail-open)。

label="codex-hook-trust"
# $HOME 自体が未設定でも死なないようにする ($HOME を直に展開すると set -u で
# unbound variable となり exit 1 = 全経路 exit 0 の契約が破れる)。空なら
# $H/.codex が存在せず SKIP に倒れる
H="${INTEGRITY_HOME:-${HOME:-}}"
# 末尾スラッシュを落としてから連結する。codex が config.toml に書いたキーは
# 正規化されたパス (`/…/.codex/hooks.json:`) なので、`//` が入ると prefix が
# 一致せず**全 entry が「未承認」**になる。`$HOME=/` のような病的ケースまでは
# 面倒を見ない (その環境なら .codex が無く SKIP に倒れる)。
# 同型の落とし穴は claude/rules/shell.md に規約化済み (issue #225)
while [ "${H%/}" != "$H" ]; do H="${H%/}"; done
hooks_json="$H/.codex/hooks.json"
cfg="$H/.codex/config.toml"

if [ ! -d "$H/.codex" ]; then
  echo "$label: SKIP ($H/.codex が無い未セットアップ環境)"
  exit 0
fi
# dangling symlink は SKIP ではなく WARN。~/.codex/hooks.json は repo への
# symlink (scripts/link.sh) なので、切れている = hook が 1 個も動いていない
# 状態そのもので、まさにこの層が拾いたいもの。-f は symlink を辿るため
# 「実体は無いが symlink はある」を -L で先に見分ける
if [ ! -f "$hooks_json" ]; then
  if [ -L "$hooks_json" ]; then
    echo "$label: WARN $hooks_json が壊れた symlink (make link 未実行? hook は 1 つも動いていない)"
    exit 0
  fi
  echo "$label: SKIP ($hooks_json が無い)"
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "$label: SKIP (jq 未導入)"
  exit 0
fi
# SHA256 は Linux の sha256sum / macOS の shasum -a 256 で取る
# (.github/scripts/install-shellcheck.sh と同じ分岐。coreutils 非前提)
if command -v sha256sum >/dev/null 2>&1; then
  sha_tool="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  sha_tool="shasum"
else
  echo "$label: SKIP (sha256sum / shasum のどちらも無い)"
  exit 0
fi

sha256_hex() {
  # stdin を sha256 して hex だけ返す。hex の切り出しに cut を挟まないのは、
  # このスクリプトが run-gate.sh 経由で毎ターン走るため (entry ごとに 1 fork 増える)。
  # ただし起動コストの支配項は cut ではなく **承認済み entry ごとの sha256 fork** と
  # config.toml 走査の方。実測 (本機・5 回連続、2026-08-03): キー存在のみの旧版
  # 0.071s / entry ごとに awk を fork した版 0.155s / 現在の 1 パス版 0.111s
  local out
  if [ "$sha_tool" = "sha256sum" ]; then
    out=$(sha256sum)
  else
    out=$(shasum -a 256)
  fi
  printf '%s' "${out%% *}"
}

# 期待 entry を "<snake_event>:<group>:<index>\t<payload JSON>" 形式で全列挙する。
# group = .hooks.<Event>[] の配列 index、index = その group の .hooks[] の index。
# `// {}` / `// []` は hooks 定義が空の hooks.json (未配線機) で
# to_entries が落ちないようにするためのもの。
#
# event 名の snake_case 化は jq 側で行う (旧版は bash の sed + tr だったが、
# payload の event_name と照合キーの event 名は**同じ問い**への答えなので、
# 2 箇所に分けると片方だけ変わって静かに食い違う)。変換規則は
# 「小文字/数字 → 大文字」の境界にだけ `_` を入れる形なので、連続大文字を
# 含むイベント名 (仮に MCPStart 等) が増えたら要見直し (外れた場合は
# キーが一致せず全件 WARN = fail-loud に倒れるので見逃しにはならない)。
#
# payload のオブジェクトは**キーをソート順に構築している** — canonical JSON は
# キー再帰ソートなので、jq が insertion order を保つ性質と合わせて `tojson` が
# そのまま canonical 形になる。並び順を変えると hash が変わり、fixture の
# 期待値定数 (tests/integrity/run-integrity-selftest.sh) が全件 FAIL する。
JQ_ENTRIES='
  (.hooks // {}) | to_entries[] | .key as $ev
  | ($ev | gsub("(?<a>[a-z0-9])(?<b>[A-Z])"; .a + "_" + .b) | ascii_downcase) as $sev
  | .value | to_entries[] | .key as $g | .value as $grp
  | ($grp.hooks // []) | to_entries[] | .key as $i | .value as $h
  | ( (if ($h.additionalContextLimit // null) == null then {}
       else { additionalContextLimit: $h.additionalContextLimit } end)
      + { async: ($h.async // false), command: ($h.command // "") }
      + (if ($h.statusMessage // null) == null then {} else { statusMessage: $h.statusMessage } end)
      + { timeout: ($h.timeout // 600), type: ($h.type // "command") } ) as $ho
  | ( { event_name: $sev, hooks: [ $ho ] }
      + (if ($grp.matcher // "") == "" then {} else { matcher: $grp.matcher } end) ) as $payload
  | "\($sev):\($g):\($i)\t\($payload | tojson)"
'

if ! entries=$(jq -r "$JQ_ENTRIES" "$hooks_json" 2>/dev/null); then
  # codex 自体が壊れている状態なので別層の問題だが、黙って skip はしない
  echo "$label: WARN $hooks_json を parse できない (hook 配線を確認すること)"
  exit 0
fi

tab=$(printf '\t')
nl='
'

# config.toml 側の承認記録を **1 パスで**取り出し、"<position>\t<hash>" の行の
# 集まりにしておく (hash が読めなかった entry は hash 側が空)。
# entry ごとに awk を fork して config.toml を読み直さないのは、このスクリプトが
# make test だけでなく run-gate.sh (= make gate、Stop hook 経由で毎ターン) から
# 走るため — 8 entry なら fork も全読みも 8 倍になる。
#
# 照合はキー行の行頭一致。パス部分まで prefix に含めるのは、別ホームの
# hooks.json に対する承認記録を自ホストの承認と取り違えないため。
# **行頭への固定を実際に効かせているのは `rest` の固定オフセット**
# (`substr($0, length(prefix) + 1)`) の方で、`index($0, prefix) == 1` は
# その前提を明示しているだけ — prefix が行の途中で見つかっても、固定オフセットで
# 切ると position が prefix の末尾数文字とずれて実 position に一致しない。
# これにより、コメント行 (`# [hooks.state."..."]`) に同じ文字列があるだけで
# 承認済みと判定される穴 (検知器が fail-open する方向) が塞がる。
# **両方を同時に「整理」しないこと** — `== 1` を `> 0` に緩めたうえで
# オフセットも `index($0, prefix) + length(prefix)` に直すと、コメント行が
# 承認記録として通る (selftest の trust-commented がその mutant で落ちる)。
#
# 照合するのは codex が書き出す basic string 書式ちょうど 1 つ。TOML 自体は
# literal string やキー周りの空白も許すので、codex が serializer を変えたら
# **全 entry が未承認扱い**になる (見逃しではなく fail-loud)。
# index() / match() をバイト単位で効かせるため LC_ALL=C 固定 (BSD awk の
# 文字境界がロケール依存になるのを避ける。キーは ASCII だがパス部分に
# 非 ASCII が混じりうる)。prefix は `-v` ではなく ENVIRON 経由で渡す —
# `-v` は代入値のバックスラッシュエスケープを解釈するため、`\` を含むパスで
# prefix が壊れて全 entry が「未承認」になる
cfg_records=""
if [ -f "$cfg" ]; then
  cfg_records=$(TRUST_KEY_PREFIX="[hooks.state.\"$hooks_json:" LC_ALL=C awk '
    BEGIN { prefix = ENVIRON["TRUST_KEY_PREFIX"] }
    index($0, prefix) == 1 {
      rest = substr($0, length(prefix) + 1)
      end = index(rest, "\"]")
      if (end > 0) {
        cur = substr(rest, 1, end - 1)
        if (!(cur in seen)) { seen[cur] = 1; order[++n] = cur; hash[cur] = "" }
      } else {
        cur = ""
      }
      next
    }
    # 次のテーブルヘッダが来たらブロックを閉じる。これが無いと、trusted_hash 行を
    # 持たないブロックの直後のテーブルに trusted_hash で始まる行があるだけで、
    # その値を前のブロックのものとして拾う (nohash → hash の fail-open)
    index($0, "[") == 1 { cur = "" }
    # `=` まで見るのは、codex が将来 trusted_hash_algo のような別キーを足したとき
    # に、先に現れたそちらを値として拾わないため
    cur != "" && hash[cur] == "" && $0 ~ /^trusted_hash[[:space:]]*=/ {
      if (match($0, /"[^"]*"/)) { hash[cur] = substr($0, RSTART + 1, RLENGTH - 2) }
    }
    END { for (i = 1; i <= n; i++) print order[i] "\t" hash[order[i]] }
  ' "$cfg")
fi
# 先頭に改行を足しておくと、1 行目の記録も「改行 + position + TAB」の形で
# 一様に照合できる (行頭アンカーの代わり)
cfg_records="$nl$cfg_records"

ok=0
unapproved=0
mismatch=0
parsefail=0
total=0

while IFS="$tab" read -r position payload; do
  [ -n "$position" ] || continue
  total=$((total + 1))

  # 承認記録を引く。config.toml が無い場合 cfg_records は空なので全 entry が
  # 未承認に倒れる — 「配線済みなのに承認記録が 1 件も無い」はまさに検知したい
  # 状態なので skip ではなく未承認として扱う。
  # `$position$tab` まで含めて照合するので、position が別 position の接頭辞
  # (0:1 と 0:10 等) でも取り違えない
  case "$cfg_records" in
    *"$nl$position$tab"*)
      recorded="${cfg_records#*"$nl$position$tab"}"
      recorded="${recorded%%"$nl"*}"
      ;;
    *)
      echo "$label: WARN 未承認の codex hook entry: $position (codex TUI で承認するまで実行されない)"
      unapproved=$((unapproved + 1))
      continue
      ;;
  esac

  # キー行はあるが trusted_hash の値が取れなかった場合。「trusted_hash 行が無い」
  # だけでなく **`trusted_hash = ""` (空の basic string)** もここに入る
  # (どちらも照合できないという点で同じなので分けない)。「承認済み」にも
  # 「未承認」にも倒さないのは、読めなかったことを OK 側に倒すと検知器が
  # fail-open するため
  if [ -z "$recorded" ]; then
    echo "$label: WARN trusted_hash を読み取れない entry: $position ($cfg の該当ブロックを確認すること)"
    parsefail=$((parsefail + 1))
    continue
  fi

  expected="sha256:$(printf '%s' "$payload" | sha256_hex)"
  if [ "$recorded" = "$expected" ]; then
    ok=$((ok + 1))
  else
    echo "$label: WARN trusted_hash 不一致: $position (記録=$recorded 期待=$expected)"
    mismatch=$((mismatch + 1))
  fi
done <<EOF
$entries
EOF

# 件数を必ず添える。「全部承認済み」と「そもそも検査対象が 0 件」を同じ `OK` で
# 出すと、この層が存在する理由 (「警告が出ない = 正常」と「そもそも動いていない」
# が区別できない) を 1 段上で再生産することになる
if [ "$total" = 0 ]; then
  echo "$label: OK (検査対象の entry が 0 件 — hooks.json に hook 定義が無い)"
elif [ "$ok" = "$total" ]; then
  echo "$label: OK ($total entry すべて承認済み・hash 一致)"
else
  echo "$label: 承認済み $ok / 未承認 $unapproved / hash 不一致 $mismatch / 読み取り不可 $parsefail (対象 $total entry)"
  if [ "$unapproved" -gt 0 ]; then
    echo "$label: 未承認の entry は codex TUI を開いて承認してください (agent からは実行不可)"
  fi
  # MISMATCH の原因は 2 つあり、**件数からは判別できない** — codex の payload
  # 仕様が変わっても、変わった規則に依存する entry しか外れないため、
  # 「仕様変更なら全件不一致」にはならない (実測: timeout の既定値を変えた
  # mutant はこの機体の 8 entry 中 1 件しか外さなかった)。かつて件数で
  # 出し分けていたが、その分岐は「再承認せよ」を誤って出す方向に倒れていた。
  # **再承認は仕様変更の証拠を消す** (codex が新しい hash を書き戻す) ので、
  # 判別材料を示して user に選ばせる形にする
  if [ "$mismatch" -gt 0 ]; then
    echo "$label: 不一致の entry は、(a) 承認後に hooks.json を書き換えた (その hook は現在実行されていない) か、(b) codex の payload 仕様が変わったかのどちらかです"
    echo "$label: その entry の hooks.json を変更した覚えがあれば (a) — codex TUI で再承認してください"
    echo "$label: 覚えが無ければ (b) を疑い、**再承認する前に** docs/ai-operations.md §10 と本スクリプトのヘッダを再実測すること (再承認すると新しい hash が書き戻され、仕様変更の証拠が消えます)"
  fi
fi
exit 0
