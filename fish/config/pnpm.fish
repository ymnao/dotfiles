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
