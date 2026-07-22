# pnpm 環境設定 (XDG Base Directory 準拠)
# pnpm add -g の書き出し先を明示。fish_add_path は idempotent なので重複追加されない
# 既に PNPM_HOME が設定されていれば尊重する (テスト時の差し替えを許容)
set -q PNPM_HOME; or set -gx PNPM_HOME $HOME/.local/share/pnpm
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
