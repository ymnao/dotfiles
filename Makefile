.PHONY: help install link update clean brewfile

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
