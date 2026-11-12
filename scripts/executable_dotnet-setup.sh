#!/data/data/com.termux/files/usr/bin/bash
# .NET Setup Script for Termux (aarch64 Android)
# Uses glibc-runner for native execution — no proot needed
set -e

DOTNET_INSTALL_DIR="$HOME/.dotnet"
CHANNEL="${1:-LTS}"

echo "=== .NET Setup for Termux (glibc-runner) ==="
echo ""

ARCH=$(uname -m)
echo "Architecture: $ARCH"
if [ "$ARCH" != "aarch64" ]; then
    echo "ERROR: This script requires aarch64. Yours: $ARCH"
    exit 1
fi

echo "Installing dependencies..."
pkg update -y
pkg install -y glibc-repo
pkg install -y glibc-runner getconf

echo "Installing .NET SDK (channel: $CHANNEL)..."
curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$PREFIX/tmp/dotnet-install.sh"
chmod +x "$PREFIX/tmp/dotnet-install.sh"
"$PREFIX/tmp/dotnet-install.sh" --channel "$CHANNEL" --install-dir "$DOTNET_INSTALL_DIR"
rm -f "$PREFIX/tmp/dotnet-install.sh"

echo "Configuring binaries for glibc-runner..."
glibc-runner -c "$DOTNET_INSTALL_DIR/dotnet"
find "$DOTNET_INSTALL_DIR" -type f \( -name "csc" -o -name "vbc" -o -name "VBCSCompiler" \) | while read -r bin; do
    if head -c4 "$bin" 2>/dev/null | grep -q "ELF"; then
        glibc-runner -c "$bin"
    fi
done

echo "Creating glibc linker symlink..."
GLIBC_LD="$PREFIX/glibc/lib/ld-linux-aarch64.so.1"
if [ -f "$GLIBC_LD" ]; then
    ln -sf "$GLIBC_LD" "$PREFIX/lib/ld-linux-aarch64.so.1"
    echo "  Symlinked: $PREFIX/lib/ld-linux-aarch64.so.1 -> $GLIBC_LD"
else
    echo "  WARNING: glibc linker not found at $GLIBC_LD"
fi

echo "Checking the dotnet wrapper..."
if [ ! -x "$HOME/.local/bin/dotnet" ]; then
    echo "ERROR: chezmoi installs the dotnet wrapper as ~/.local/bin/dotnet. Run chezmoi apply, then this script again."
    exit 1
fi
export PATH="$HOME/.local/bin:$PATH"

# Export env for build/verify steps (before .bashrc is sourced)
# .bashrc env vars are managed by chezmoi — not this script
export TMPDIR="$PREFIX/tmp"
export DOTNET_ROOT="$DOTNET_INSTALL_DIR"
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
export DOTNET_GCHeapHardLimit=1C0000000
export DOTNET_gcServer=0

echo "Building vstest patcher..."
PATCHER_DIR="$HOME/scripts/patch-vstest"
if [ -f "$PATCHER_DIR/patch-vstest.csproj" ]; then
    dotnet build "$PATCHER_DIR" -c Release --nologo -v quiet && echo "  Patcher built" || echo "  WARNING: Patcher build failed (dotnet test may not work under proot)"
else
    echo "  Patcher project not found at $PATCHER_DIR, skipping"
fi

echo ""
echo "=== Verifying ==="
dotnet --version && dotnet --list-sdks && dotnet --list-runtimes
echo ""
echo "=== SUCCESS ==="
echo "Run 'source ~/.bashrc' or restart your shell."
echo "Usage: dotnet new console -o myapp && cd myapp && dotnet run"
