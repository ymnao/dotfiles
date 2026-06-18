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

brewfile: ## Update Brewfile with currently installed packages
	@brew bundle dump --force --file=Brewfile
	@echo "Brewfile updated"

lint: ## Run secretlint to detect leaked secrets
	@command -v secretlint >/dev/null || { \
	    echo "secretlint not installed."; \
	    echo "Install: npm i -g @secretlint/secretlint @secretlint/secretlint-rule-preset-recommend"; \
	    exit 1; \
	}
	@secretlint --secretlintignore .gitignore "**/*"

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
