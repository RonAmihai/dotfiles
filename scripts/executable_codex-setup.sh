#!/data/data/com.termux/files/usr/bin/bash
# Codex CLI Setup Script for Termux (aarch64 Android)
# Installs/updates the official standalone package (codex-package-<target>.tar.gz)
# from GitHub releases, in the same layout as the official install.sh
# (~/.codex/packages/standalone/{releases/<ver>-<target>,current}). Codex refuses
# to start the TUI from a bare binary. Static musl, so no glibc-runner needed;
# the chezmoi wrapper at ~/.local/bin/codex runs it via termux-chroot.
set -e

REPO="openai/codex"
TARGET="aarch64-unknown-linux-musl"
ASSET="codex-package-$TARGET.tar.gz"
SUMS="codex-package_SHA256SUMS"
STANDALONE="$HOME/.codex/packages/standalone"
RELEASES="$STANDALONE/releases"
CURRENT_LINK="$STANDALONE/current"

# Install dependencies (skip if already installed)
NEED_DEPS=false
for dep in termux-tools proot gh; do
    dpkg -s "$dep" &>/dev/null || { NEED_DEPS=true; break; }
done
if $NEED_DEPS; then
    echo "  Installing dependencies..."
    pkg update -y
    pkg install -y termux-tools proot gh
fi

# Remove older install methods: TUR package ($PREFIX/bin/codex would shadow the
# wrapper) and the bare binary from earlier versions of this script
if dpkg -s codex &>/dev/null; then
    echo "  Removing TUR codex package..."
    pkg uninstall -y codex &>/dev/null
fi
rm -rf "$HOME/.local/share/codex"

TAG=$(gh api "repos/$REPO/releases/latest" --jq '.tag_name' 2>/dev/null || true)
VERSION=${TAG#rust-v}
if [ -z "$TAG" ]; then
    echo "  Failed to query latest release (is gh authenticated?)"
    exit 1
fi

CURRENT=""
if [ -x "$CURRENT_LINK/bin/codex" ]; then
    CURRENT=$("$CURRENT_LINK/bin/codex" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
fi

if [ "$CURRENT" = "$VERSION" ]; then
    echo "  ${VERSION} (up to date)"
else
    echo "  ${CURRENT:-not installed} -> ${VERSION}"
    STAGING="$RELEASES/.staging.$$"
    TMP="$PREFIX/tmp/codex-dl.$$"
    trap 'rm -rf "$STAGING" "$TMP"' EXIT
    mkdir -p "$TMP" "$STAGING"
    BASE="https://github.com/$REPO/releases/download/$TAG"
    if ! curl -fsSL -o "$TMP/$SUMS" "$BASE/$SUMS" || ! curl -fsSL -o "$TMP/$ASSET" "$BASE/$ASSET"; then
        echo "  Download failed, keeping current version"
        exit 1
    fi
    if ! (cd "$TMP" && grep " $ASSET\$" "$SUMS" | sha256sum -c --status); then
        echo "  Checksum mismatch, keeping current version"
        exit 1
    fi
    tar -xzf "$TMP/$ASSET" -C "$STAGING"
    chmod 0755 "$STAGING/bin/codex" "$STAGING/bin/codex-code-mode-host" "$STAGING/codex-path/rg"
    [ -f "$STAGING/codex-resources/bwrap" ] && chmod 0755 "$STAGING/codex-resources/bwrap"
    ln -sf "bin/codex" "$STAGING/codex"

    RELEASE_DIR="$RELEASES/$VERSION-$TARGET"
    rm -rf "$RELEASE_DIR"
    mv "$STAGING" "$RELEASE_DIR"
    ln -sfn "releases/$VERSION-$TARGET" "$CURRENT_LINK.new"
    mv -Tf "$CURRENT_LINK.new" "$CURRENT_LINK"
    echo "  Updated to ${VERSION}"

    # Prune old releases
    find "$RELEASES" -mindepth 1 -maxdepth 1 ! -name "$VERSION-$TARGET" -exec rm -rf {} +
fi

# Restore the chezmoi wrapper if missing or replaced (e.g. by the official installer)
if [ -L "$HOME/.local/bin/codex" ] || [ ! -f "$HOME/.local/bin/codex" ]; then
    rm -f "$HOME/.local/bin/codex"
    chezmoi apply --force "$HOME/.local/bin/codex" 2>/dev/null || true
fi
