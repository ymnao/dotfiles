.PHONY: help install link update clean brewfile lint test

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

test: ## Verify shell scripts (shellcheck) and JSON files (jq)
	@command -v shellcheck >/dev/null || { echo "shellcheck not installed. Run: brew install shellcheck"; exit 1; }
	@command -v jq >/dev/null || { echo "jq not installed. Run: brew install jq"; exit 1; }
	@echo "==> shellcheck (warning level and above)"
	@git ls-files '*.sh' | xargs shellcheck -S warning
	@echo "==> JSON validation"
	@git ls-files '*.json' | while read -r f; do \
	    jq empty "$$f" >/dev/null || { echo "FAIL: $$f"; exit 1; }; \
	done
	@echo "OK: all checks passed"
