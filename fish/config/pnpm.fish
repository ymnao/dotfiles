# pnpm 環境設定 (XDG Base Directory 準拠)
# pnpm add -g の書き出し先を明示。fish_add_path は idempotent なので重複追加されない
# ユーザーが既に PNPM_HOME を設定していれば尊重する (公式 install script や
# テストからの差し替えを想定)。空文字列 set は default 扱いにしたいので
# test -n で除外する
set -q PNPM_HOME; and test -n "$PNPM_HOME"; or set -gx PNPM_HOME $HOME/.local/share/pnpm
fish_add_path -g $PNPM_HOME/bin

# npm を封じて pnpm への一本化を促す (advisory)
# 緊急時は `command npm ...` で bypass 可能
function npm --description "Block npm; use pnpm instead"
    echo "npm はこの環境では封じています。pnpm を使ってください:" >&2
    echo "  install → pnpm install    run → pnpm run    exec → pnpm exec    dlx → pnpm dlx" >&2
    echo "  どうしても npm が必要なときは 'command npm ...' で bypass できます" >&2
    return 1
end

function npx --description "Block npx; use pnpm dlx instead"
    echo "npx はこの環境では封じています。'pnpm dlx' を使ってください" >&2
    echo "  bypass: 'command npx ...'" >&2
    return 1
end

# 依存と GitHub Actions をまとめて更新する (pnpm 11.16+)。
# 常時有効化する `update.githubActions` は **repo の pnpm-workspace.yaml にしか
# 置けず** グローバル設定では無視されるため (pnpm 11.25.0 で実測)、
# repo をまたいで効かせる手段としてフラグを abbr に置く。
# `--latest` は major を越えるので既定にしない (`pnua --latest` と手で足す)。
abbr -a pnua 'pnpm update --include-github-actions'
