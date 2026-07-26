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
#
# tests/integrity/run-integrity-check.sh との役割分担:
#   - run-integrity-check.sh = 構造の検査 (~/.claude ~/.codex の symlink が
#     期待どおりの実体を指しているか)。ズレは異常なので exit 1 で落とす
#   - この hook = 内容の検査 (repo 内 hook 実装の未コミット改変)。dotfiles の
#     開発中は dirty が正常状態なので **落とさず警告だけ** 出す
#
# 検査対象は「host 側でコマンドを起動する定義」に限る:
#   agents/hooks/ (正本) / claude/hooks/ / codex/hooks/ (symlink + codex 固有実体)
#   codex/hooks.json / claude/settings.json (どちらも hook の command を定義する)
# codex/skills/ と claude/skills/ は対象外 — skill は model への指示テキストで
# あって host が直接実行するものではなく、脅威モデルが異なる。
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
export LC_ALL=C

command -v git >/dev/null 2>&1 || exit 0

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

# host 側で実行される定義のみを対象にする (冒頭コメント参照)
porcelain=$(git -C "$repo" status --porcelain=v1 -uall -- \
  agents/hooks \
  claude/hooks \
  codex/hooks \
  codex/hooks.json \
  claude/settings.json 2>/dev/null) || exit 0

[ -n "$porcelain" ] || exit 0

count=$(printf '%s\n' "$porcelain" | grep -c . || true)

echo "[hooks-integrity] 警告: host 実行される hook 定義に未コミットの変更があります (${count} 件)"
printf '%s\n' "$porcelain" | head -20
cat <<'EOF'
これらは commit されていなくても、次回の Claude Code / codex 起動時に host 側で
実行されます (codex の trusted_hash はスクリプト本体を検査しないため再承認は
走りません)。意図した編集かを確認してください。詳細: docs/ai-operations.md §10
EOF

exit 0
