#!/data/data/com.termux/files/usr/bin/bash
# Termux Initial Environment Setup
# Bootstrap script for a fresh Termux installation.
# Installs packages, applies dotfiles via chezmoi, and optionally sets up
# .NET SDK, Claude Code, Codex CLI, and Antigravity CLI.
#
# Usage (fresh install):
#   pkg upgrade -y && pkg install -y git gh && { gh auth status &>/dev/null || gh auth login; } && { gh api 'repos/RonAmihai/dotfiles/contents/scripts/executable_termux-setup.sh?ref=main' --jq '.content' | base64 -d | bash; }
#
# Usage (after chezmoi apply):
#   termux-setup.sh
set -e

echo "=== Termux Environment Setup ==="
echo ""
# Android refuses an add-on app that another store signed
if [ -n "${TERMUX_APK_RELEASE:-}" ]; then
    echo "Install Termux add-on apps from the same source as Termux ($TERMUX_APK_RELEASE)"
    echo ""
fi

# 1. Update and install essential packages; chezmoi's package script installs the rest
echo "[1/5] Installing packages..."
pkg update -y
pkg upgrade -y
pkg install -y \
    zsh \
    jq \
    chezmoi \
    git \
    gh \
    glab-cli \
    openssh \
    curl \
    which \
    fastfetch \
    termux-api \
    termux-tools \
    glibc-repo
pkg install -y \
    glibc-runner \
    proot

# 2. Create directory structure
echo "[2/5] Creating directories..."
mkdir -p ~/.local/bin ~/.shortcuts ~/scripts

# 3. Apply dotfiles
echo "[3/5] Setting up dotfiles..."
export PATH="$HOME/.local/bin:$HOME/scripts:$PATH"

if [ ! -d "$HOME/.local/share/chezmoi" ]; then
    echo "  Applying dotfiles..."
    chezmoi init RonAmihai --apply --promptDefaults
else
    echo "  Updating dotfiles..."
    chezmoi update --apply
fi

# 4. Authenticate CLI tools
echo "[4/5] CLI authentication..."
if ! gh auth status &>/dev/null 2>&1; then
    echo "  Authenticating with GitHub..."
    gh auth login --hostname github.com --git-protocol https --web
else
    echo "  GitHub: already authenticated"
fi

if ! glab auth status &>/dev/null 2>&1; then
    echo "  GitLab: not authenticated (run 'glab auth login --hostname gitlab.com' manually)"
else
    echo "  GitLab: already authenticated"
fi

# 5. Optional tool setup
echo "[5/5] Optional tools..."
echo ""

read -p "  Install .NET SDK? [y/N] " install_dotnet </dev/tty
if [[ "$install_dotnet" == [yY] ]]; then
    if [ -f "$HOME/scripts/dotnet-setup.sh" ]; then
        "$HOME/scripts/dotnet-setup.sh"
    else
        echo "  dotnet-setup.sh not found — run chezmoi apply first"
    fi
fi

echo ""
read -p "  Install Claude Code? [y/N] " install_claude </dev/tty
if [[ "$install_claude" == [yY] ]]; then
    if [ -f "$HOME/scripts/claude-setup.sh" ]; then
        "$HOME/scripts/claude-setup.sh"
    else
        echo "  claude-setup.sh not found — run chezmoi apply first"
    fi
fi

echo ""
read -p "  Install Codex CLI? [y/N] " install_codex </dev/tty
if [[ "$install_codex" == [yY] ]]; then
    if [ -f "$HOME/scripts/codex-setup.sh" ]; then
        "$HOME/scripts/codex-setup.sh"
    else
        echo "  codex-setup.sh not found — run chezmoi apply first"
    fi
fi

echo ""
read -p "  Install Antigravity CLI (agy)? [y/N] " install_agy </dev/tty
if [[ "$install_agy" == [yY] ]]; then
    if [ -f "$HOME/scripts/agy-setup.sh" ]; then
        "$HOME/scripts/agy-setup.sh"
    else
        echo "  agy-setup.sh not found — run chezmoi apply first"
    fi
fi

# Reload settings
termux-reload-settings 2>/dev/null || true

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Close Termux fully and open it again. New sessions start in zsh."
echo ""
echo "Installed: the packages in ~/.config/termux/packages.txt"
echo ""
echo "Optional (if skipped, run manually later):"
echo "  ~/scripts/dotnet-setup.sh    — Install .NET SDK"
echo "  ~/scripts/claude-setup.sh    — Install Claude Code"
echo "  ~/scripts/codex-setup.sh     — Install Codex CLI"
echo "  ~/scripts/agy-setup.sh       — Install Antigravity CLI"
