#!/usr/bin/env bash
# Usage: bash tools/ci/render-diff.sh CHEZMOI CONFIG BASE_REF [ALLOWED] — renders BASE_REF and the working tree into empty HOMEs, prints the diff, and fails when a file that the ALLOWED list does not name differs
set -euo pipefail

chezmoi=$1
config=$2
base_ref=$3
allowed=$(grep -v -e '^#' -e '^$' "${4:-/dev/null}" || true)
repo=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir "$tmp/base-src"
git -C "$repo" archive "$base_ref" | tar -x -C "$tmp/base-src"

render() {
    mkdir "$tmp/$2"
    "$chezmoi" --config "$config" --source "$1" --destination "$tmp/$2" --persistent-state "$tmp/$2.boltdb" \
        apply --exclude externals,scripts --no-tty --force
}
render "$tmp/base-src" base
render "$repo" head

changed_files() {
    { (cd base && find . \( -type f -o -type l \)); (cd head && find . \( -type f -o -type l \)); } | sed 's|^\./||' | sort -u |
    while IFS= read -r f; do
        if [ -L "base/$f" ] && [ -L "head/$f" ]; then
            [ "$(readlink "base/$f")" = "$(readlink "head/$f")" ] && continue
        elif [ -f "base/$f" ] && [ ! -L "base/$f" ] && [ -f "head/$f" ] && [ ! -L "head/$f" ]; then
            cmp -s "base/$f" "head/$f" && continue
        fi
        echo "$f"
    done
}

cd "$tmp"
diff -r --no-dereference base head && exit 0
unexpected=$(changed_files | grep -vxF -e "${allowed:-//none//}" || true)
if [ -n "$unexpected" ]; then
    echo "render-diff: these files differ, and the allowlist does not name them:"
    printf '%s\n' "$unexpected" | sed 's/^/  /'
    exit 1
fi
echo "render-diff: every file that differs is on the allowlist"
