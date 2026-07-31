#!/usr/bin/env bash
set -uo pipefail

# codex hook の承認状態 (trusted_hash 登録) を検査する warn-only 層 (issue #239)。
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
# 検査: codex/hooks.json (host からは ~/.codex/hooks.json) の各 hook entry に
# 対応する [hooks.state] キーが ~/.codex/config.toml にあるかを見る。
#
# キー書式は codex-cli 0.146.0 の ~/.codex/config.toml から実測 (2026-07-31)。
#
# **限界 (キー存在しか見ていない)**: trusted_hash の値そのものは検証しない
# (検証には codex upstream のハッシュ入力仕様が要る。未調査)。したがって
# 「承認後に hooks.json の command を書き換えた」ケースで古いキーが残るなら
# この検査は「承認済み」と誤って報告する。**この残存挙動自体は未検証**
# (再現には承認済みの状態が要るが、本機の対象 entry は未承認のため作れない)。
# trusted_hash の再実測は issue #214 が担当する。
#
# 検知時: **警告のみで exit 0**。承認は user 操作でしか行えず、agent が
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

# 期待 entry を "<Event>:<group>:<index>" 形式で全列挙する。
# group = .hooks.<Event>[] の配列 index、index = その group の .hooks[] の index。
# `// {}` / `// []` は hooks 定義が空の hooks.json (未配線機) で
# to_entries が落ちないようにするためのもの。
if ! entries=$(jq -r '
  (.hooks // {}) | to_entries[] | .key as $ev
  | .value | to_entries[] | .key as $g
  | ((.value.hooks // []) | length) as $n
  | range($n)
  | "\($ev):\($g):\(.)"' "$hooks_json" 2>/dev/null); then
  # codex 自体が壊れている状態なので別層の問題だが、黙って skip はしない
  echo "$label: WARN $hooks_json を parse できない (hook 配線を確認すること)"
  exit 0
fi

# config.toml はループ中ずっと不変なので 1 度だけ読む (entry ごとに grep を
# fork してファイルを読み直さない)。存在しない場合は空のままにして全 entry を
# WARN に倒す — 「配線済みなのに承認記録が 1 件も無い」はまさに検知したい状態
nl='
'
cfg_content=""
if [ -f "$cfg" ]; then
  # 先頭に改行を足しておくと、ファイル 1 行目のキーも「改行 + キー」の形で
  # 一様に照合できる (行頭アンカーの代わり)
  cfg_content="$nl$(cat "$cfg")"
fi

warn=0
prev_event=""
snake=""

while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  event="${entry%%:*}"
  position="${entry#*:}"

  # codex の state キーは event 名を snake_case で持つ (PreToolUse → pre_tool_use)。
  # 既知 4 イベントのハードコード表にしないのは、hooks.json に未知のイベントが
  # 増えたときに黙って検査対象から漏れるため — それはこの検査が塞ごうとしている
  # 「配線したのに検知ゼロ件」と同型の穴になる。
  # 同じ event が複数 entry にまたがる (1 group に複数 hook / 複数 group) ので、
  # 変換結果は event が変わったときだけ計算し直す (sed + tr の 2 fork/entry を節約)。
  # 変換規則は「小文字/数字 → 大文字」の境界にだけ `_` を入れる形なので、
  # 連続大文字を含むイベント名 (仮に MCPStart 等) が増えたら要見直し
  # (外れた場合は全件 WARN = fail-loud に倒れるので見逃しにはならない)
  if [ "$event" != "$prev_event" ]; then
    snake=$(printf '%s' "$event" \
      | LC_ALL=C sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' \
      | LC_ALL=C tr '[:upper:]' '[:lower:]')
    prev_event="$event"
  fi

  # 照合はキーの行頭一致。パス部分まで含めるのは、別ホームの hooks.json に
  # 対する承認記録を自ホストの承認と取り違えないため。行頭に固定するのは、
  # コメント行 (`# [hooks.state."..."]`) に同じ文字列があるだけで承認済みと
  # 判定されるのを防ぐため (検知器が fail-open する方向の穴になる)。
  # case の pattern 側は quote 済み展開なので、キー中の [ ] " はリテラル扱いになる。
  # 照合するのは codex が書き出す basic string 書式ちょうど 1 つ。TOML 自体は
  # literal string やキー周りの空白も許すので、codex が serializer を変えたら
  # **全 entry が WARN** になる (見逃しではなく fail-loud)。全件 WARN になったら
  # まず書式変更を疑うこと
  key="[hooks.state.\"$hooks_json:$snake:$position\"]"

  case "$cfg_content" in
    *"$nl$key"*) ;;
    *)
      echo "$label: WARN 未承認の codex hook entry: $snake:$position (codex TUI で承認するまで実行されない)"
      warn=1
      ;;
  esac
done <<EOF
$entries
EOF

if [ "$warn" = 0 ]; then
  echo "$label: OK"
else
  echo "$label: 未承認の entry があります。codex TUI を開いて承認してください (agent からは実行不可)"
fi
exit 0
