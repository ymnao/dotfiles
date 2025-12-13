# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with this dotfiles repository.

## Overview

This is a personal dotfiles repository for managing development environment configurations. The repository includes configurations for WezTerm, Neovim, Karabiner-Elements, Fish shell, Git, and various development tools.

## Repository Structure

```
dotfiles/
├── fish/                    # Fish shell configuration
│   ├── config.fish         # Main Fish config
│   └── config/             # Modular configs
├── git/                    # Git configuration
│   ├── config              # Public Git config (symlinked to ~/.config/git/config)
│   ├── config.local.template  # Template for private settings
│   └── ignore              # Global gitignore (symlinked to ~/.config/git/ignore)
├── karabiner/              # Karabiner-Elements keyboard config
├── nvim/                   # Neovim configuration
│   ├── init.lua           # Entry point
│   ├── lazy-lock.json     # Lazy.nvim plugin lockfile
│   └── lua/               # Lua configuration modules
├── wezterm/                # WezTerm terminal configuration
│   ├── wezterm.lua        # Main config
│   ├── keymaps.lua        # Key bindings
│   ├── tab_bar.lua        # Tab bar customization
│   └── colors/            # Color schemes
├── scripts/                # Automation scripts
│   ├── install.sh         # Full installation script
│   └── link.sh            # Symlink creation script
├── .gitignore              # Repository gitignore
├── .secretlintrc.json      # Security linting config
├── Brewfile                # Homebrew package list
├── Makefile                # Task runner
└── README.md               # Documentation
```

## Key Configuration Files

### Fish Shell
- **Location**: `fish/config.fish`
- **Modular configs**: `fish/config/*.fish`
- Sets XDG directories, editor (nvim), pager, and PATH

### Git
- **Public config**: `git/config` (symlinked to `~/.config/git/config`)
- **Global ignore**: `git/ignore` (symlinked to `~/.config/git/ignore`)
- **Private config**: `~/.config/git/config.local` (NOT tracked, created from template)
- Uses `delta` for diffs, includes helpful aliases
- **XDG-compliant**: All Git config files are in `~/.config/git/`
- **Important**: Never commit `~/.config/git/config.local` - it contains personal information

### WezTerm
- **Main config**: `wezterm/wezterm.lua`
- Modular organization with separate files for keymaps, colors, and features
- Supports Kanagawa and OneDark color schemes

### Neovim
- **Entry point**: `nvim/init.lua`
- Uses Lazy.nvim for plugin management
- Lockfile: `nvim/lazy-lock.json`

### Karabiner
- **Config**: `karabiner/karabiner.json`
- Customizes keyboard mappings for macOS

## Installation Workflow

### Initial Setup
```bash
# Clone repository to development directory
git clone https://github.com/YOUR_USERNAME/dotfiles.git ~/development/important/dotfiles
cd ~/development/important/dotfiles

# Run installation (installs Homebrew, packages, creates symlinks)
make install

# OR manually
bash scripts/install.sh
```

### Creating Symlinks Only
```bash
make link
# OR
bash scripts/link.sh
```

### Updating Packages
```bash
make update
```

## Security & Privacy

### Files NOT Tracked
- `.DS_Store` - macOS metadata
- `*.log` - Log files
- `*.local`, `*.private` - Local/private configurations
- `.env`, `.env.*` - Environment variables
- `automatic_backups/` - Karabiner backups
- `.claude/` - Claude Code settings
- `gh/hosts.yml` - GitHub CLI auth info

### Personal Information
- User name and email are in `~/.config/git/config.local` (NOT tracked)
- Template available at `git/config.local.template`
- Always use `.local` suffix for private overrides

## Development Workflow

### Making Changes
1. Edit configuration files in the repository
2. Changes are immediately reflected (dotfiles are symlinked)
3. For WezTerm: reload with `Cmd+Shift+R` (macOS) or `Ctrl+Shift+R` (Linux)
4. For Fish: reload with `exec fish`
5. For Neovim: restart or `:source $MYVIMRC`

### Git Workflow
- Create feature branches for significant changes
- Use descriptive commit messages
- Run `make lint` before committing to check for secrets

### Adding New Tools
1. Add configuration files to appropriate directory
2. Update `scripts/link.sh` to create symlinks
3. If it's a Homebrew package, update `Brewfile` with `make brewfile`
4. Update `README.md` and this file with new tool documentation

## Common Tasks

### Update Brewfile
```bash
make brewfile
```

### Check for Secrets
```bash
make lint
```

### Clean Broken Symlinks
```bash
make clean
```

### Run All Tests
```bash
make test
```

## Best Practices

1. **Never commit secrets**: Always check with `make lint` before committing
2. **Use `.local` for overrides**: Create `.local` versions of configs for machine-specific settings
3. **Keep it modular**: Split large configs into smaller, focused files
4. **Document changes**: Update README.md and CLAUDE.md when adding new features
5. **Test before pushing**: Run `make test` to ensure configurations are valid

## Platform Support

- **Primary**: macOS (Apple Silicon and Intel)
- **Secondary**: Linux (tested on Ubuntu/Debian)
- Scripts detect OS and adjust behavior accordingly

## Dependencies

### Required
- Git
- Bash (for install scripts)

### Optional (installed by install.sh)
- Homebrew (macOS)
- Fish shell
- Neovim
- WezTerm
- Node.js (for secretlint)

## Troubleshooting

### Symlinks Not Working
```bash
# Remove and recreate
make clean
make link
```

### Git Config Issues
```bash
# Ensure ~/.config/git/config.local exists
cp git/config.local.template ~/.config/git/config.local
# Edit with your information
nvim ~/.config/git/config.local
```

### Homebrew Issues
```bash
# Update and cleanup
make update
```

## References

- [dotfiles.github.io](https://dotfiles.github.io/) - Dotfiles best practices
- [awesome-dotfiles](https://github.com/webpro/awesome-dotfiles) - Curated dotfiles resources
