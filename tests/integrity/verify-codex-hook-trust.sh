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
# **限界 (キー存在しか見ていない)**: 承認後に hooks.json の command を
# 書き換えた場合、codex は hash 不一致で再承認を求めるが古いキーは残るため、
# この検査は「承認済み」と誤って報告する。trusted_hash の値そのものを
# 検証するには codex upstream のハッシュ入力仕様が要る (未調査)。
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
H="${INTEGRITY_HOME:-$HOME}"
hooks_json="$H/.codex/hooks.json"
cfg="$H/.codex/config.toml"

if [ ! -d "$H/.codex" ]; then
  echo "$label: SKIP ($H/.codex が無い未セットアップ環境)"
  exit 0
fi
if [ ! -f "$hooks_json" ]; then
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
cfg_content=""
if [ -f "$cfg" ]; then
  cfg_content=$(cat "$cfg")
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
  # 変換結果は event が変わったときだけ計算し直す (sed + tr の 2 fork/entry を節約)
  if [ "$event" != "$prev_event" ]; then
    snake=$(printf '%s' "$event" \
      | LC_ALL=C sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' \
      | LC_ALL=C tr '[:upper:]' '[:lower:]')
    prev_event="$event"
  fi

  # 照合はキー行の完全一致。パス部分まで含めるのは、別ホームの hooks.json に
  # 対する承認記録を自ホストの承認と取り違えないため。
  # case の pattern 側は quote 済み展開なので、キー中の [ ] " はリテラル扱いになる
  key="[hooks.state.\"$hooks_json:$snake:$position\"]"

  case "$cfg_content" in
    *"$key"*) ;;
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
