#!/usr/bin/env bash
# Usage: bash tools/ci/termux-ci.sh — inside termux/termux-docker, renders this repo into an empty HOME and runs every Termux check on it
set -uo pipefail

src=$(cd "$(dirname "$0")/../.." && pwd)
status=0
step() {
    echo "== $1"
    shift
    "$@" || { echo "FAILED: $*"; status=1; }
}

apt-get update -qq >/dev/null && apt-get install -y -qq zsh chezmoi git jq proot python openssh oh-my-posh >/dev/null || exit 1
git config --global --add safe.directory '*'
# The git-hooks script writes into the source's .git, so the source must be writable
work=$(mktemp -d)
cp -R "$src" "$work/src"
printf '[data]\n    name = "CI"\n' > "$work/chezmoi.toml"
home=$work/home
mkdir "$home"
cm() {
    CI=true chezmoi --config "$work/chezmoi.toml" --source "$work/src" --destination "$home" --persistent-state "$work/state.boltdb" "$@"
}

step "apply" cm apply --exclude externals --no-tty --force
ln -sf "$PREFIX/bin/oh-my-posh" "$home/.local/bin/oh-my-posh"
step "fresh-home-check" bash "$work/src/tools/shell-check/fresh-home-check.sh" --home "$home"
step "check-termux" bash "$work/src/tools/ci/check-termux.sh" "$home"
step "check-work-profile" bash "$work/src/tools/ci/check-work-profile.sh" "$home"
step "check-rendered-files" bash "$work/src/tools/ci/check-rendered-files.sh" "$home"
step "update-all dry run" env XDG_CONFIG_HOME="$home/.config" zsh "$home/.local/bin/update-all" --dry-run
step "second apply" cm apply --exclude externals --no-tty --force
left=$(cm status --exclude externals)
if [ -n "$left" ]; then
    echo "FAILED: a second apply would still change:"
    echo "$left"
    status=1
fi
exit "$status"
