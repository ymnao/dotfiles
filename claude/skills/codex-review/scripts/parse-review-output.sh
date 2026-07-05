#!/usr/bin/env bash
set -euo pipefail

# codex exec の出力から review JSON を抽出・検証する。
#
# stdin : codex の生出力 (JSON フェンスブロックを含む想定)
# stdout: 検証済み JSON (1 行)
# exit  : 0 = verdict pass / 2 = findings あり / 1 = パース・検証エラー
#
# 抽出戦略: 最後の ```json フェンスブロックを採用する (codex が前置きの
# 散文を書いても耐える)。フェンスがなければ出力全体を JSON として試す。
# verdict=pass なのに findings が非空の矛盾出力は安全側で findings 扱い。

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 1
fi

raw=$(cat)

json=$(printf '%s\n' "$raw" | awk '
  /^```json[[:space:]]*$/ { buf=""; inblk=1; next }
  /^```[[:space:]]*$/     { if (inblk) { last=buf; inblk=0 }; next }
  inblk                   { buf = buf $0 "\n" }
  END                     { printf "%s", last }
')
if [ -z "$json" ]; then
  json=$raw
fi

if ! validated=$(printf '%s' "$json" | jq -ce '
  if ((.perspective | type) == "string")
     and (.verdict == "pass" or .verdict == "findings")
     and ((.findings | type) == "array")
     and ([ .findings[]
            | select(
                ((.severity == "HIGH" or .severity == "MEDIUM" or .severity == "LOW") | not)
                or ((.confidence | type) != "number")
                or (.confidence < 0 or .confidence > 100)
                or ((.file | type) != "string")
                or ((.line | type) != "number")
                or (.line < 0)
                or ((.issue | type) != "string")
                or ((.fix | type) != "string")
              )
          ] | length == 0)
  then .
  else error("schema mismatch")
  end
' 2>/dev/null); then
  echo "ERROR: could not parse codex output as review JSON. Raw head:" >&2
  # awk 'NR<=20' は全入力を読み切るので printf が SIGPIPE で 141 終了しない。
  # set -euo pipefail のもとで `head -20` を使うと、raw が長いと printf が
  # SIGPIPE を受けてパイプが非ゼロで終わり、下の exit 1 に到達せず 141 で
  # 落ちる (parse error は exit 1 の契約が破れる)。
  printf '%s\n' "$raw" | awk 'NR<=20' >&2
  exit 1
fi

# verdict=pass で findings 非空は矛盾出力。exit code だけでなく JSON の
# verdict も "findings" に正規化してから出力する。exit code を見ない下流が
# あっても JSON 単独で契約を判定できる。
if printf '%s' "$validated" | jq -e '.verdict == "pass" and (.findings | length) == 0' >/dev/null; then
  printf '%s\n' "$validated"
  exit 0
fi
printf '%s' "$validated" | jq -c '.verdict = "findings"'
exit 2
