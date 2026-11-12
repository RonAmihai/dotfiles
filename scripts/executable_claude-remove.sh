#!/data/data/com.termux/files/usr/bin/bash
# Claude Code Removal Script for Termux
set -e

echo "=== Claude Code Removal for Termux ==="
echo ""

read -p "This will remove Claude Code data and aliases. Continue? [y/N] " confirm </dev/tty
if [[ "$confirm" != [yY] ]]; then
    echo "Cancelled."
    exit 0
fi

echo "Removing Claude Code data..."
rm -rf "$HOME/.claude"
rm -f "$HOME/.claude.json"

echo "Removing native binary..."
rm -rf "$HOME/.local/share/claude"
rm -f "$HOME/.local/bin/claude"

echo "Clearing old npx cache..."
NPX_CACHE="$HOME/.npm/_npx"
if [ -d "$NPX_CACHE" ]; then
    find "$NPX_CACHE" -maxdepth 2 -name "node_modules" -type d | while read -r dir; do
        if ls "$dir"/@anthropic-ai/claude-code 2>/dev/null; then
            rm -rf "$(dirname "$dir")"
            echo "  Removed cached claude-code package"
        fi
    done
fi

echo ""
echo "=== Claude Code removed ==="
echo "glibc-runner was kept (other apps may use it)."
echo "To remove it too: pkg uninstall glibc-runner"
echo "Note: .bashrc is managed by chezmoi — remove aliases there if needed."
