#!/usr/bin/env bash
# Usage: bash tools/ci/check-scripts.sh — runs shellcheck on every standalone sh or bash script. The shell tool files are not here, because they mix in zsh code that shellcheck cannot parse; fresh-home-check.sh tests those in zsh and bash instead
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
files=()
while IFS= read -r file; do
    head -n 1 "$file" | grep -qE '^#!((/usr/bin/env |/bin/)(ba)?sh|/data/data/com\.termux/files/usr/bin/bash( -l)?)$' && files+=("$file")
done < <(find "$repo/dot_local/bin" "$repo/.githooks" "$repo/scripts" "$repo/dot_shortcuts" -type f; find "$repo/tools" -type f -name '*.sh')
shellcheck -S warning "${files[@]}"
echo "check-scripts: shellcheck passed on ${#files[@]} scripts"
