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
#     type            — 既定 "command"
#     command         — hooks.json のまま
#     async           — 既定 false
#     timeout         — **hooks.json に無いときの既定は 600**
#     statusMessage   — hooks.json に無いときはキーごと省略
#
# 根拠: この機体の ~/.codex/config.toml に記録済みの trusted_hash 6 件すべてを
# バイト一致で再現した (issue #214)。0.145.0 時点では 5/6 で、未再現だった
# Stop entry の原因が上記 2 つの既定・省略規則 (matcher 空の省略 / timeout 600)
# だった。canonical JSON の生成は jq の insertion order + tojson に依存する
# (下の JQ_ENTRIES はキーをソート順に構築している)。
#
# **これらは codex の実装詳細なので upgrade で変わりうる**。変わった場合は
# 計算値が全 entry で外れるため **全 entry が MISMATCH** になる (見逃しではなく
# fail-loud)。全件 MISMATCH になったらまず payload 仕様の変更を疑い、
# docs/ai-operations.md §10 を再実測して更新すること。一部 entry だけの
# MISMATCH は意味が違い、「承認後に hooks.json を書き換えた」= その hook は
# 現在実行されていない、を指す。
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
  # stdin を sha256 して hex だけ返す
  if [ "$sha_tool" = "sha256sum" ]; then
    sha256sum | cut -d' ' -f1
  else
    shasum -a 256 | cut -d' ' -f1
  fi
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
  | ( { async: ($h.async // false), command: ($h.command // "") }
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

ok=0
unapproved=0
mismatch=0
parsefail=0
total=0

while IFS="$tab" read -r position payload; do
  [ -n "$position" ] || continue
  total=$((total + 1))

  # 照合はキーの行頭一致。パス部分まで含めるのは、別ホームの hooks.json に
  # 対する承認記録を自ホストの承認と取り違えないため。行頭に固定するのは、
  # コメント行 (`# [hooks.state."..."]`) に同じ文字列があるだけで承認済みと
  # 判定されるのを防ぐため (検知器が fail-open する方向の穴になる)。
  # 照合するのは codex が書き出す basic string 書式ちょうど 1 つ。TOML 自体は
  # literal string やキー周りの空白も許すので、codex が serializer を変えたら
  # **全 entry が WARN** になる (見逃しではなく fail-loud)
  key="[hooks.state.\"$hooks_json:$position\"]"

  # config.toml から当該ブロックの trusted_hash を取り出す。TOML の正規パーサは
  # 使わず行スキャンなので、結果は 3 値で返す:
  #   absent — キー行が無い (= 未承認)
  #   nohash — キー行はあるが trusted_hash 行が読めない (= 判断できない)
  #   hash:<値> — 読めた
  # nohash を「承認済み」にも「未承認」にも倒さないのは、読めなかったことを
  # OK 側に倒すと検知器が fail-open するため。
  # index() / match() をバイト単位で効かせるため LC_ALL=C 固定 (BSD awk の
  # 文字境界がロケール依存になるのを避ける。キーは ASCII だがパス部分に
  # 非 ASCII が混じりうる)
  if [ -f "$cfg" ]; then
    recorded=$(LC_ALL=C awk -v key="$key" '
      index($0, key) == 1 { inblock = 1; found = 1; next }
      inblock && index($0, "[") == 1 { inblock = 0 }
      inblock && !got && index($0, "trusted_hash") == 1 {
        if (match($0, /"[^"]*"/)) { val = substr($0, RSTART + 1, RLENGTH - 2); got = 1 }
      }
      END {
        if (got) print "hash:" val
        else if (found) print "nohash"
        else print "absent"
      }' "$cfg")
  else
    # config.toml が無い = 承認記録が 1 件も無い。「配線済みなのに承認記録が
    # ゼロ」はまさに検知したい状態なので skip ではなく未承認として扱う
    recorded="absent"
  fi

  case "$recorded" in
    absent)
      echo "$label: WARN 未承認の codex hook entry: $position (codex TUI で承認するまで実行されない)"
      unapproved=$((unapproved + 1))
      continue
      ;;
    nohash)
      echo "$label: WARN trusted_hash を読み取れない entry: $position ($cfg の該当ブロックを確認すること)"
      parsefail=$((parsefail + 1))
      continue
      ;;
  esac

  expected="sha256:$(printf '%s' "$payload" | sha256_hex)"
  if [ "${recorded#hash:}" = "$expected" ]; then
    ok=$((ok + 1))
  else
    echo "$label: WARN trusted_hash 不一致: $position (記録=${recorded#hash:} 期待=$expected)"
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
  # 不一致が「hash を照合できた entry すべて」に及ぶなら、個々の hooks.json 変更
  # ではなく payload 仕様そのものが変わった可能性が高い。一部だけなら逆に、
  # その entry が承認後に書き換えられた = 現在実行されていない、を意味する
  if [ "$mismatch" -gt 0 ] && [ "$mismatch" = "$((ok + mismatch))" ]; then
    echo "$label: hash を照合できた entry が全件不一致 — codex の payload 仕様変更を疑い docs/ai-operations.md §10 を再実測すること"
  elif [ "$mismatch" -gt 0 ]; then
    echo "$label: 不一致の entry は承認後に hooks.json が変更された可能性 (その hook は現在実行されていない)。codex TUI で再承認してください"
  fi
fi
exit 0
