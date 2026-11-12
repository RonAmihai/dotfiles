#!/data/data/com.termux/files/usr/bin/bash
# Claude Code Setup Script for Termux (aarch64 Android)
# Installs the native Claude Code binary via glibc-runner
set -e

INSTALL_DIR="$HOME/.local/share/claude"
GCS_BUCKET="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

# Install dependencies (skip if already installed)
NEED_DEPS=false
for dep in glibc-runner termux-tools proot; do
    dpkg -s "$dep" &>/dev/null || { NEED_DEPS=true; break; }
done
if $NEED_DEPS; then
    echo "  Installing dependencies..."
    pkg update -y
    pkg install -y glibc-repo
    pkg install -y glibc-runner termux-tools proot
fi
# The binary asks for /lib/ld-linux-aarch64.so.1, which inside termux-chroot is this link
ln -sf "$PREFIX/glibc/lib/ld-linux-aarch64.so.1" "$PREFIX/lib/ld-linux-aarch64.so.1"

# Check versions — fetch remote and local in parallel
TMPVER="$PREFIX/tmp/claude-latest.$$"
curl -fsSL -o "$TMPVER" "$GCS_BUCKET/latest" &
CURL_PID=$!
CURRENT=""
if [ -x "$INSTALL_DIR/claude-native" ]; then
    CURRENT=$("$HOME/.local/bin/termux-glibc-exec" "$INSTALL_DIR/claude-native" --version 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' || true)
fi
wait $CURL_PID
VERSION=$(cat "$TMPVER" 2>/dev/null)
rm -f "$TMPVER"

if [ "$CURRENT" = "$VERSION" ]; then
    echo "  ${VERSION} (up to date)"
else
    echo "  ${CURRENT:-not installed} -> ${VERSION}"
    mkdir -p "$INSTALL_DIR"
    TMPBIN="$PREFIX/tmp/claude-native.$$"
    if curl -fsSL -o "$TMPBIN" "$GCS_BUCKET/$VERSION/linux-arm64/claude"; then
        chmod +x "$TMPBIN"
        mv "$TMPBIN" "$INSTALL_DIR/claude-native"
        echo "  Updated to ${VERSION}"
        CURRENT="$VERSION"
    else
        echo "  Download failed, keeping current version"
        rm -f "$TMPBIN"
    fi
fi

# Clean up stale artifacts from older install methods
# Remove versioned binaries directory (we use claude-native now)
[ -d "$INSTALL_DIR/versions" ] && rm -rf "$INSTALL_DIR/versions"
# If ~/.local/bin/claude is a symlink (left by native installer) or missing, replace with chezmoi wrapper
if [ -L "$HOME/.local/bin/claude" ] || [ ! -f "$HOME/.local/bin/claude" ]; then
    rm -f "$HOME/.local/bin/claude"
    chezmoi apply --force "$HOME/.local/bin/claude" 2>/dev/null || true
fi

# Wrapper and .bashrc are managed by chezmoi — not this script

