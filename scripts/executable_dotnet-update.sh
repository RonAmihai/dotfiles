#!/data/data/com.termux/files/usr/bin/bash
# .NET Update Script for Termux (aarch64 Android)
# Usage:
#   dotnet-update.sh              # latest LTS
#   dotnet-update.sh 9.0          # latest on channel 9.0
#   dotnet-update.sh 9.0.311      # exact version 9.0.311
set -e

DOTNET_INSTALL_DIR="$HOME/.dotnet"
export DOTNET_NOLOGO=1
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
INPUT="${1:-LTS}"

# Detect if input is an exact version (x.y.z) or a channel (x.y / STS / LTS)
if [[ "$INPUT" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    VERSION="$INPUT"
    CHANNEL=""
else
    VERSION=""
    CHANNEL="$INPUT"
fi

if [ -n "$VERSION" ]; then
    echo "  Channel: $VERSION (exact)"
else
    local_major=${CHANNEL%%.*}
    if [[ "$local_major" =~ ^[0-9]+$ ]] && [ $((local_major % 2)) -eq 0 ]; then
        echo "  Channel: $CHANNEL (LTS)"
    else
        echo "  Channel: $CHANNEL"
    fi
fi

# Capture current version for this channel before updating
OLD_VER=$(dotnet --list-sdks 2>/dev/null | grep "^${CHANNEL:-$VERSION}" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' | tail -1)

# Download and run the official install script
curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$PREFIX/tmp/dotnet-install.sh"
chmod +x "$PREFIX/tmp/dotnet-install.sh"
INSTALL_ARGS=(--install-dir "$DOTNET_INSTALL_DIR")
if [ -n "$VERSION" ]; then
    INSTALL_ARGS+=(--version "$VERSION")
else
    INSTALL_ARGS+=(--channel "$CHANNEL")
fi

# Capture output to detect if anything was actually installed
INSTALL_OUTPUT=$("$PREFIX/tmp/dotnet-install.sh" "${INSTALL_ARGS[@]}" 2>&1) || {
    echo "$INSTALL_OUTPUT"
    rm -f "$PREFIX/tmp/dotnet-install.sh"
    exit 1
}
rm -f "$PREFIX/tmp/dotnet-install.sh"

INSTALLED_VER=$(echo "$INSTALL_OUTPUT" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if echo "$INSTALL_OUTPUT" | grep -q "is already installed"; then
    echo "  $INSTALLED_VER (up to date)"
    exit 0
fi

if [ -n "$OLD_VER" ] && [ "$OLD_VER" != "$INSTALLED_VER" ]; then
    echo "  ${OLD_VER} -> ${INSTALLED_VER}"
    # Remove old SDK version from the same channel
    if [ -d "$DOTNET_INSTALL_DIR/sdk/$OLD_VER" ]; then
        rm -rf "$DOTNET_INSTALL_DIR/sdk/$OLD_VER"
    fi
else
    echo "  Updated to ${INSTALLED_VER}"
fi

# Re-patch binaries for glibc-runner
echo "  Reconfiguring binaries for glibc-runner..."
glibc-runner -c "$DOTNET_INSTALL_DIR/dotnet"
find "$DOTNET_INSTALL_DIR" -type f \( -name "csc" -o -name "vbc" -o -name "VBCSCompiler" \) | while read -r bin; do
    if head -c4 "$bin" 2>/dev/null | grep -q "ELF"; then
        glibc-runner -c "$bin"
    fi
done

# Clear vstest patch marker so the patcher re-runs for the new SDK
rm -f "$DOTNET_INSTALL_DIR/.vstest-patched"
rm -f "$DOTNET_INSTALL_DIR"/sdk/*/Microsoft.TestPlatform.CoreUtilities.dll.orig

# Rebuild the vstest patcher
PATCHER_DIR="$HOME/scripts/patch-vstest"
if [ -f "$PATCHER_DIR/patch-vstest.csproj" ]; then
    echo "  Rebuilding vstest patcher..."
    dotnet build "$PATCHER_DIR" -c Release --nologo -v quiet && echo "  Patcher built" || echo "  WARNING: Patcher build failed"
fi

echo "  $(dotnet --list-sdks | tr '\n' ', ' | sed 's/, $//')"
