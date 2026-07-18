.PHONY: help install link update clean brewfile lint test test-hooks gate

# Default target
.DEFAULT_GOAL := help

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install: ## Install dotfiles and dependencies
	@bash scripts/install.sh

link: ## Create symlinks for dotfiles
	@bash scripts/link.sh

update: ## Update Homebrew packages
	@# Brewfile 記載パッケージが未インストール状態でないかを先にチェックし、
	@# 乖離があれば fail-fast する (upgrade は数分かかるので順序が重要)。
	@# check は non-destructive、一方向 = Brewfile 記載 → 実インストールのみ。
	@# 逆方向 (未記載だがインストール済み) は check では検出できず、
	@# 破壊的な bundle cleanup / dump を避けるため今回はスコープ外。
	@# cleanup は Brewfile 手動編集の構造を破壊するため使わない (CLAUDE.md 参照)。
	@# --greedy は auto_updates cask (claude-code 等) の版遅延を拾うが、
	@#   cask 側の更新頻度に依存するため常時採用はせず、今回は check のみ。
	@echo "==> Brewfile 記載パッケージのインストール状態チェック"
	@brew bundle check --file=Brewfile --verbose || { \
	    echo ""; \
	    echo "HINT: 未インストールのパッケージがある。brew bundle install で導入するか、Brewfile から該当行を削除する (make brewfile は使わない)"; \
	    exit 1; \
	}
	@brew update && brew upgrade && brew cleanup

clean: ## Remove broken symlinks
	@find ~ -maxdepth 1 -type l ! -exec test -e {} \; -delete
	@find ~/.config -maxdepth 1 -type l ! -exec test -e {} \; -delete 2>/dev/null || true

brewfile: ## Regenerate Brewfile from installed packages (destructive; requires FORCE=1)
	@# brew bundle dump --force は Brewfile のセクション・コメント・trusted:
	@# オプションを全て破壊する。Brewfile は手動編集が正 (CLAUDE.md 参照)。
	@if [ "$(FORCE)" != "1" ]; then \
	    echo "ERROR: make brewfile destroys Brewfile sections/comments/trusted: options."; \
	    echo "Brewfile is maintained by hand (see CLAUDE.md). To run anyway: make brewfile FORCE=1"; \
	    exit 1; \
	fi
	@brew bundle dump --force --file=Brewfile
	@echo "Brewfile updated"

lint: ## Run secretlint to detect leaked secrets
	@command -v pnpm >/dev/null || { echo "pnpm not installed. Run: brew install pnpm"; exit 1; }
	@# 毎回 pnpm install を実行する。node_modules の存在判定だけで省略すると、
	@# 旧 version の secretlint が node_modules に残っている環境で lockfile
	@# 更新が反映されない。lockfile 一致時はほぼ no-op で軽量。
	@pnpm install
	@# 追跡ファイルのみ走査する。未追跡のローカル秘密 (.env, secrets/,
	@# .claude/settings.local.json 等) を「コミット前チェック」の対象外に
	@# する。git add -f で誤って追跡された場合は走査対象に戻る。
	@git ls-files -z | xargs -0 pnpm exec secretlint --

test: ## Verify shell scripts (shellcheck), JSON files (jq), and hooks
	@command -v shellcheck >/dev/null || { echo "shellcheck not installed. Run: brew install shellcheck"; exit 1; }
	@command -v jq >/dev/null || { echo "jq not installed. Run: brew install jq"; exit 1; }
	@echo "==> shellcheck (warning level and above)"
	@# symlink 除外: claude/hooks と codex/hooks は agents/hooks への symlink なので実体だけ検査する。
	@# SC2088 の局所無効化は agents/hooks/.shellcheckrc に委譲 (editor/CI 直 shellcheck も継承)。
	@git ls-files '*.sh' | while read -r f; do [ -L "$$f" ] || printf '%s\n' "$$f"; done | xargs shellcheck -S warning
	@echo "==> JSON validation"
	@git ls-files '*.json' | while read -r f; do \
	    jq empty "$$f" >/dev/null || { echo "FAIL: $$f"; exit 1; }; \
	done
	@echo "==> TOML validation"
	@command -v python3 >/dev/null || { echo "python3 not installed"; exit 1; }
	@# tomllib は Python 3.11+ 標準。3.10 以下だと import で ModuleNotFoundError
	@# となり意味不明な失敗になるため、明示的に version を検証する。
	@python3 -c "import sys; sys.exit(0 if sys.version_info >= (3,11) else 1)" \
	    || { echo "python3 >= 3.11 required (tomllib は 3.11+ の標準ライブラリ)"; exit 1; }
	@# starship.toml の `\$` 系 escape ミス等、Rust 側 lenient parser では
	@# 通ってしまう仕様外の TOML を CI で FAIL させる。
	@git ls-files '*.toml' | while read -r f; do \
	    python3 -c "import tomllib,sys; tomllib.load(open(sys.argv[1],'rb'))" "$$f" || { echo "FAIL: $$f"; exit 1; }; \
	done
	@bash tests/run-hook-tests.sh
	@bash tests/parse-review-output/run-parser-tests.sh
	@bash tests/classify-risk/run-classify-risk-tests.sh
	@bash tests/dependabot-bulk-classifier/run-classifier-tests.sh
	@bash tests/agents-md-sync/run-agents-md-sync-check.sh
	@bash tests/statusline/run-statusline-tests.sh
	@bash tests/stop-verify-gate/run-stop-gate-tests.sh
	@bash tests/post-format/run-post-format-tests.sh
	@bash tests/hooks-glob/run-glob-determinism-tests.sh
	@bash tests/link-backup/run-link-backup-tests.sh
	@bash tests/verify-ci/run-verify-ci-tests.sh
	@bash tests/integrity/run-integrity-selftest.sh
	@bash tests/integrity/verify-guard-codex-wiring.sh
	@bash tests/session-compact/run-session-compact-tests.sh
	@bash tests/fish-pnpm/run-fish-pnpm-tests.sh
	@echo "OK: all checks passed"

test-hooks: ## Run hook regression tests
	@bash tests/run-hook-tests.sh

gate: ## Fast verification gate (used by the Stop hook; full checks = make test)
	@command -v jq >/dev/null || { echo "jq not installed. Run: brew install jq"; exit 1; }
	@bash tests/run-gate.sh
