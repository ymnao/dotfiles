#!/usr/bin/env bash
#
# SessionStart hook (Claude Code, matcher: startup|resume): host 側で実行される
# hook 定義に未コミットの変更があれば警告する (warn-only)。
# 正本: agents/hooks/hooks-integrity-warn.sh (claude/hooks/ からは相対 symlink)
#
# 背景 (issue #207): codex CLI の hook 承認 (~/.codex/config.toml の
# [hooks.state].trusted_hash) は **hook の設定 identity のみ** をハッシュしており、
# 参照先スクリプト本体は一切含まれない (codex 0.145.0 で実測。詳細は
# docs/ai-operations.md §10)。つまり ~/.codex/hooks/*.sh の中身を差し替えても
# codex は再承認を求めず、次回起動時に無警告で host 側で実行する。
# ~/.codex/hooks.json / hooks/ は dotfiles repo への symlink なので、
# 「repo 内のファイルを編集したが commit していない」状態がそのまま
# host 実行される窓になる。この repo の cwd は sandbox の allowWrite なので、
# その編集自体は正当な開発と区別できない。
#
# そこで予防 (block) ではなく **検知** で受ける。commit されていれば PR review と
# integrity check の対象になるため、危ないのは「未コミットの改変」だけ。
# 防御層全体の位置づけ・役割分担・残余リスクは docs/ai-operations.md §10 を参照
# (ここでは「構造検査の run-integrity-check.sh とは対になる内容検査であり、
# dotfiles 開発中は dirty が正常状態なので落とさず警告だけ出す」とだけ押さえる)。
#
# cwd 非依存: SessionStart は任意のプロジェクトで発火するため、検査対象の
# dotfiles repo は「このスクリプト自身の実体パス」から導出する
# (HOOKS_INTEGRITY_REPO で上書き可 — テスト用)。
#
# stdin は読まない。SessionStart の payload に必要な情報が無い (cwd は使わない)
# うえ、tests/run-gate.sh からも呼ぶため、stdin 無しで起動されても待たない
# ようにしておく。
#
# fail-open: git 不在・repo を特定できない・git コマンド失敗ではいずれも
# 何も出さず exit 0。検知層であって遮断層ではないので、誤検知で作業を
# 止めないことを優先する。
#
# exit code は常に 0 (warn-only)。set -e は使わず個別に失敗を捕捉する。

set -uo pipefail

# git plumbing の出力をバイト単位で安定させるため C ロケールに固定する
# (--porcelain の書式自体はロケール非依存だが、pathname の照合と
# `grep -c` の行カウントがロケール依存の文字解釈に引きずられないようにする)。
# 副作用として make test-locale-matrix の UTF-8 軸はこのファイルに効かなくなるので、
# 日本語直前の変数展開は自分でブレース (`${var}`) を徹底すること (claude/rules/shell.md)。
export LC_ALL=C

# 監視対象は「host 側で起動されるコマンドを **直接** 定義しているファイル」に限る:
#   agents/hooks/ (正本) / claude/hooks/ / codex/hooks/ (symlink + codex 固有実体)
#   codex/hooks.json / claude/settings.json (hook と statusLine の command 定義)
#   .claude/stop-gate.conf (Stop hook が bash -c に渡す検証コマンド)
#   claude/statusline.sh (settings.json の statusLine から毎回起動される)
#
# 意図的に含めないもの:
#   - codex/skills/ と claude/skills/ — skill は model への指示テキストであって
#     host が直接実行するものではなく、脅威モデルが異なる
#   - tests/ / Makefile / scripts/ — stop-gate.conf の `make gate` 経由で間接的に
#     host 実行されるが、ここまで広げるとこの repo のほぼ全変更で警告が出て
#     signal が消える。「repo に書ける主体は host でコードを実行できる」という
#     前提そのものは docs/ai-operations.md §10 に明記してある
#
# 配線されている実行ファイルがこの一覧から漏れていないことは
# tests/hooks-integrity/run-hooks-integrity-tests.sh が assert する
# (`--list-watched` はそのための出力口)。
WATCHED_PATHS=(
  agents/hooks
  claude/hooks
  codex/hooks
  codex/hooks.json
  claude/settings.json
  claude/statusline.sh
  .claude/stop-gate.conf
)

if [ "${1:-}" = "--list-watched" ]; then
  printf '%s\n' "${WATCHED_PATHS[@]}"
  exit 0
fi

command -v git >/dev/null 2>&1 || exit 0

# HOOKS_INTEGRITY_REPO は呼び出し側が repo root を既に知っている場合の近道
# (tests/run-gate.sh / テスト)。値の妥当性は検証しない — この env を仕込める
# 主体は既に host でコードを実行できており、検証を足しても防御にならない一方、
# 検証失敗時の fallback は「別 repo を黙って見に行く」という分かりにくい
# 誤動作を生む (実装中に実際に踏んだ)。
repo="${HOOKS_INTEGRITY_REPO:-}"
if [ -z "$repo" ]; then
  # symlink 経由 (~/.claude/hooks/ → dotfiles/claude/hooks/) で起動されるため、
  # pwd -P で実体側に解決してから repo root を求める。
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P) || exit 0
  [ -n "$script_dir" ] || exit 0
  repo=$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
fi
[ -n "$repo" ] || exit 0
[ -d "$repo" ] || exit 0

porcelain=$(git -C "$repo" status --porcelain=v1 -uall -- "${WATCHED_PATHS[@]}" 2>/dev/null) || exit 0

[ -n "$porcelain" ] || exit 0

count=$(printf '%s\n' "$porcelain" | grep -c . || true)
limit=20

echo "[hooks-integrity] 警告: host 実行される hook 定義に未コミットの変更があります (${count} 件)"
printf '%s\n' "$porcelain" | head -"$limit"
if [ "$count" -gt "$limit" ]; then
  echo "  ... 他 $((count - limit)) 件 (先頭 ${limit} 件のみ表示)"
fi
cat <<'EOF'
これらは commit されていなくても、次回の Claude Code / codex 起動時に host 側で
実行されます (codex の trusted_hash はスクリプト本体を検査しないため再承認は
走りません)。意図した編集かを確認してください。詳細: docs/ai-operations.md §10
EOF

exit 0
