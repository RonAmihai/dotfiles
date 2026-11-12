#!/usr/bin/env bash
# Usage: bash tools/ci/check-git-bash-wrapper.sh — in Git Bash without zsh, update-all and clean-all must map their flags to PowerShell switches and stop on any other argument
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
pwsh.exe() { printf '%s\n' "$*"; }
export DOTFILES_PHASE=aliases
. "$repo/dot_config/shell/tools/update-all.sh"

expect() {
    [ "$1" = "$2" ] || { echo "check-git-bash-wrapper: expected \"$2\", got \"$1\"" >&2; exit 1; }
}
expect "$(update-all --dry-run)" '-NoLogo -Command Update-All -DryRun'
expect "$(update-all --skip-os-updates -SkipWSL)" '-NoLogo -Command Update-All -SkipOSUpdates -SkipWSL'
expect "$(clean-all --dry-run)" '-NoLogo -Command Clean-All -DryRun'
if update-all brew 2>/dev/null; then
    echo 'check-git-bash-wrapper: update-all ran with an argument that has no Windows meaning' >&2
    exit 1
fi
echo 'check-git-bash-wrapper: update-all and clean-all pass the right switches'
