#!/data/data/com.termux/files/usr/bin/bash
# Antigravity CLI (agy) Setup Script for Termux (aarch64 Android)
# Installs/updates the native Android (bionic) build — no glibc-runner needed.
# The official install.sh is not used: inside termux-chroot `uname -o` reports
# GNU/Linux so it picks the glibc build, and it runs `agy install`, which edits
# shell profiles (.bashrc is owned by chezmoi).
set -e

BINARY_PATH="$HOME/.local/bin/agy"
MANIFEST_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/android_arm64.json"

# Fetch manifest
manifest=$(curl -fsSL "$MANIFEST_URL" 2>/dev/null || true)
if [ -z "$manifest" ]; then
    echo "  Failed to fetch release manifest"
    exit 1
fi

parse_json_key() {
    echo "$manifest" | sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}
VERSION=$(parse_json_key version)
URL=$(parse_json_key url)
SHA512=$(parse_json_key sha512)

if [ -z "$VERSION" ] || [ -z "$URL" ] || [ -z "$SHA512" ]; then
    echo "  Failed to parse release manifest"
    exit 1
fi

CURRENT=""
if [ -x "$BINARY_PATH" ]; then
    CURRENT=$("$BINARY_PATH" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
fi

if [ "$CURRENT" = "$VERSION" ]; then
    echo "  ${VERSION} (up to date)"
    exit 0
fi

echo "  ${CURRENT:-not installed} -> ${VERSION}"
STAGING="$PREFIX/tmp/agy-staging.$$"
mkdir -p "$STAGING"
trap 'rm -rf "$STAGING"' EXIT

if ! curl -fsSL -o "$STAGING/agy.tar.gz" "$URL"; then
    echo "  Download failed, keeping current version"
    exit 1
fi

ACTUAL=$(sha512sum "$STAGING/agy.tar.gz" | cut -d' ' -f1)
if [ "$ACTUAL" != "$SHA512" ]; then
    echo "  Checksum mismatch, keeping current version"
    exit 1
fi

tar -xzf "$STAGING/agy.tar.gz" -C "$STAGING" antigravity
mkdir -p "$(dirname "$BINARY_PATH")"
install -m 755 "$STAGING/antigravity" "$BINARY_PATH.new"
mv "$BINARY_PATH.new" "$BINARY_PATH"
echo "  Updated to ${VERSION}"
