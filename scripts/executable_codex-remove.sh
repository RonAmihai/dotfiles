#!/data/data/com.termux/files/usr/bin/bash
# Codex CLI Removal Script for Termux
set -e

echo "=== Codex CLI Removal for Termux ==="
echo ""

read -p "This will remove Codex CLI and its data (~/.codex). Continue? [y/N] " confirm </dev/tty
if [[ "$confirm" != [yY] ]]; then
    echo "Cancelled."
    exit 0
fi

echo "Removing standalone package and wrapper..."
rm -rf "$HOME/.local/share/codex"
rm -f "$HOME/.local/bin/codex"

if dpkg -s codex &>/dev/null; then
    echo "Uninstalling TUR package..."
    pkg uninstall -y codex
fi

echo "Removing Codex data..."
rm -rf "$HOME/.codex"

echo ""
echo "=== Codex CLI removed ==="
echo "Note: ~/.local/bin/codex wrapper is managed by chezmoi — 'chezmoi apply' restores it."
