#!/usr/bin/env bash
# Usage: bash tools/shell-check/check-this-machine.sh — renders this repo and each dotfiles layer of this machine into a temporary home, and runs the checks that fit this system on it
set -uo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
home=$tmp/home
mkdir -p "$home"
printf '[data]\n    name = "check"\n' > "$tmp/public.toml"
printf '# A layer needs no data\n' > "$tmp/layer.toml"

render() {
    if ! chezmoi --config "$2" --source "$1" --destination "$home" --persistent-state "$3" \
        apply --exclude scripts,externals --no-tty --force </dev/null >/dev/null 2>"$tmp/render.err"; then
        cat "$tmp/render.err"
        echo "FAIL: chezmoi cannot render $1"
        exit 1
    fi
}

# Each layer goes between two renders of this repo, so the templates here read the layers' data, as on a real apply
render "$repo" "$tmp/public.toml" "$tmp/public.db"
layers=''
for source in "$HOME"/.local/share/chezmoi-*; do
    [ -d "$source" ] || continue
    name=${source##*/chezmoi-}
    if [ "$name" = work ]; then
        echo "skip: the work layer stays out, because with it the work command refuses to start"
        continue
    fi
    render "$source" "$tmp/layer.toml" "$tmp/$name.db"
    layers="$layers $name"
done
[ -z "$layers" ] || render "$repo" "$tmp/public.toml" "$tmp/public.db"
echo "== rendered this repo${layers:+ and the layers:$layers}"
command -v oh-my-posh >/dev/null 2>&1 && ln -sf "$(command -v oh-my-posh)" "$home/.local/bin/oh-my-posh"

status=0
run() {
    echo "== $1"
    shift
    "$@" </dev/null || status=1
}
run "shell check" bash "$repo/tools/shell-check/fresh-home-check.sh" --home "$home"
run "rendered files" bash "$repo/tools/ci/check-rendered-files.sh" "$home"
run "templates" bash "$repo/tools/ci/check-templates.sh" "$(command -v chezmoi)" "$tmp/public.toml"
run "status line" bash "$repo/tools/ci/check-statusline.sh"
if [ -x /data/data/com.termux/files/usr/bin/pkg ]; then
    run "Termux" bash "$repo/tools/ci/check-termux.sh" "$home"
else
    run "JetBrains" bash "$repo/tools/ci/check-jetbrains.sh" "$(command -v chezmoi)" "$tmp/public.toml"
fi
run "work command" bash "$repo/tools/ci/check-work-profile.sh" "$home"

echo
if [ "$status" = 0 ]; then
    echo "All checks passed"
else
    echo "Some checks failed: see the FAIL lines above"
fi
exit "$status"
