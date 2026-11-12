#!/data/data/com.termux/files/usr/bin/bash
# .NET Removal Script for Termux (aarch64 Android)
set -e

echo "=== .NET Removal for Termux ==="
echo ""

read -p "This will remove .NET SDK and all related files. Continue? [y/N] " confirm </dev/tty
if [[ "$confirm" != [yY] ]]; then
    echo "Cancelled."
    exit 0
fi

# Remove .NET installation
echo "Removing ~/.dotnet..."
rm -rf "$HOME/.dotnet"

# Remove NuGet cache
echo "Removing ~/.nuget..."
rm -rf "$HOME/.nuget"

# Remove template engine cache
echo "Removing ~/.templateengine..."
rm -rf "$HOME/.templateengine"

# Remove the wrapper script
echo "Removing dotnet wrapper..."
rm -f "$PREFIX/bin/dotnet"

# Remove vstest patcher build artifacts
echo "Removing vstest patcher build artifacts..."
rm -rf "$HOME/scripts/patch-vstest/bin" "$HOME/scripts/patch-vstest/obj"

echo ""
echo "=== .NET removed ==="
echo "Note: .bashrc env vars are managed by chezmoi — remove them there if needed."
echo ""
echo "glibc-runner and its loader link $PREFIX/lib/ld-linux-aarch64.so.1 were kept (Claude Code needs them)."
echo "To remove it too: pkg uninstall glibc-runner"
echo "Run 'source ~/.bashrc' or restart your shell."
