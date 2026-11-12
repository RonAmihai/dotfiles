#!/usr/bin/env bash
# Usage: bash tools/ci/termux-installers.sh — inside termux/termux-docker, applies this repo to HOME and runs the real Claude Code, Codex and agy installers
set -uo pipefail

src=$(cd "$(dirname "$0")/../.." && pwd)
status=0

apt-get update -qq >/dev/null && apt-get install -y -qq chezmoi git gh jq proot curl >/dev/null || exit 1
git config --global --add safe.directory '*'
work=$(mktemp -d)
cp -R "$src" "$work/src"
printf '[data]\n    name = "CI"\n' > "$work/chezmoi.toml"
CI=true chezmoi --config "$work/chezmoi.toml" --source "$work/src" --persistent-state "$work/state.boltdb" \
    apply --exclude externals,scripts --no-tty --force || exit 1
export PATH="$HOME/.local/bin:$HOME/scripts:$PATH"
for tool in claude codex agy; do
    echo "== $tool"
    if "$HOME/scripts/$tool-setup.sh" && "$tool" --version; then
        echo "ok: $tool installs and runs"
    else
        echo "FAILED: $tool"
        status=1
    fi
done
exit "$status"
