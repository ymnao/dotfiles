#!/usr/bin/env bash
#
# PreToolUse hook (Codex CLI): パッケージインストールコマンドをブロックする
#
# allowlist 方式: 以下のみ許可し、それ以外のパッケージマネージャ呼び出しをブロック
#   - npm ci（ロックファイルからの復元）
#   - npm install / npm i（引数なし、ロックファイルからの復元）
#   - pnpm install（引数なし）
#   - yarn install（引数なし）
#
# exit 0 = 許可, exit 2 = ブロック
#

input=$(cat)

case "$input" in
  *npm*|*npx*|*pnpm*|*yarn*|*bun*|*pip*|*uv*|*poetry*) ;;
  *) exit 0 ;;
esac

if ! command -v jq &>/dev/null; then
  echo "ブロック: jq 未インストールのためパッケージインストールを確認できません" >&2
  exit 2
fi

command=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty')

if [[ -z "$command" ]]; then
  exit 0
fi

# npm ci は常に許可（ロックファイルからの復元）
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])npm[[:space:]]+ci([[:space:]]|[;&|)}`]|$)'; then
  exit 0
fi

# npx / npm exec (alias: x) は未導入パッケージを実行時取得し得るためブロック
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])(npx|npm[[:space:]]+(exec|x))([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: npx / npm exec は実行時にパッケージを取得し得るため禁止されています" >&2
  exit 2
fi

# npm install とその公式 alias が引数なし（末尾またはセパレータ直後）なら許可
# （ロックファイルからの復元）。引数ありはすべてブロック（--save-dev react の
# ようなフラグ挟みも含む）。alias 集合は npm help install / install-test の列挙に従う
npm_install_aliases='(install|i|add|in|ins|inst|insta|instal|isnt|isnta|isntal|isntall|install-test|it)'
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])npm[[:space:]]+'"$npm_install_aliases"'([[:space:]]|[;&|)}`]|$)'; then
  if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])npm[[:space:]]+'"$npm_install_aliases"'([[:space:]]*[;&|)}`]|[[:space:]]*$)'; then
    exit 0
  fi
  echo "ブロック: npm install <package>（alias 含む）は禁止されています。パッケージの追加はユーザーに依頼してください" >&2
  exit 2
fi

# pnpm add は常にブロック、pnpm install は引数なしのみ許可
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])pnpm[[:space:]]+add([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: pnpm add は禁止されています。パッケージの追加はユーザーに依頼してください" >&2
  exit 2
fi
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])pnpm[[:space:]]+dlx([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: pnpm dlx は実行時にパッケージを取得するため禁止されています" >&2
  exit 2
fi
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])pnpm[[:space:]]+(install|i)([[:space:]]|[;&|)}`]|$)'; then
  if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])pnpm[[:space:]]+(install|i)([[:space:]]*[;&|)}`]|[[:space:]]*$)'; then
    exit 0
  fi
  echo "ブロック: pnpm install <package>（alias: i）は禁止されています。パッケージの追加はユーザーに依頼してください" >&2
  exit 2
fi

# yarn add は常にブロック（yarn global add 含む）、yarn install は引数なしのみ許可
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])yarn[[:space:]]+(global[[:space:]]+)?add([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: yarn add は禁止されています。パッケージの追加はユーザーに依頼してください" >&2
  exit 2
fi
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])yarn[[:space:]]+dlx([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: yarn dlx は実行時にパッケージを取得するため禁止されています" >&2
  exit 2
fi
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])yarn[[:space:]]+install([[:space:]]|[;&|)}`]|$)'; then
  if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])yarn[[:space:]]+install([[:space:]]*[;&|)}`]|[[:space:]]*$)'; then
    exit 0
  fi
  echo "ブロック: yarn install <package> は禁止されています。パッケージの追加はユーザーに依頼してください" >&2
  exit 2
fi

# bun は lockfile 復元もパッケージ追加も現行 allowlist 外のためブロック
# （a は add の、i は install の公式 alias）
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])bun[[:space:]]+(add|a|install|i)([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: bun add/install は許可リスト外です。パッケージ操作はユーザーに依頼してください" >&2
  exit 2
fi
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])(bunx|bun[[:space:]]+x)([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: bunx は実行時にパッケージを取得し得るため禁止されています" >&2
  exit 2
fi

# pip install は常にブロック（uv pip install も含む）
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])(pip|pip3|uv[[:space:]]+pip)[[:space:]]+install([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: pip install は禁止されています。パッケージの追加はユーザーに依頼してください" >&2
  exit 2
fi

if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])pipx[[:space:]]+(install|inject|run)([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: pipx install/inject/run はパッケージを取得し得るため禁止されています" >&2
  exit 2
fi

# uv add は常にブロック
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])uv[[:space:]]+add([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: uv add は禁止されています。パッケージの追加はユーザーに依頼してください" >&2
  exit 2
fi
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])uv[[:space:]]+tool[[:space:]]+(install|run)([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: uv tool install/run はパッケージを取得し得るため禁止されています" >&2
  exit 2
fi
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])uvx([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: uvx は実行時にパッケージを取得するため禁止されています" >&2
  exit 2
fi

# poetry add は常にブロック
if printf '%s\n' "$command" | grep -qE '(^|[;&|({`[:space:]])poetry[[:space:]]+add([[:space:]]|[;&|)}`]|$)'; then
  echo "ブロック: poetry add は禁止されています。パッケージの追加はユーザーに依頼してください" >&2
  exit 2
fi

exit 0
