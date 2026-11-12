#!/data/data/com.termux/files/usr/bin/bash
# Antigravity CLI (agy) Removal Script for Termux
set -e

echo "=== Antigravity CLI Removal for Termux ==="
echo ""

read -p "This will remove the agy binary and its cache. Continue? [y/N] " confirm </dev/tty
if [[ "$confirm" != [yY] ]]; then
    echo "Cancelled."
    exit 0
fi

echo "Removing binary..."
rm -f "$HOME/.local/bin/agy"

echo "Removing cache..."
rm -rf "$HOME/.cache/antigravity"

echo ""
echo "=== Antigravity CLI removed ==="
