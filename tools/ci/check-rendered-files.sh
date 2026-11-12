#!/usr/bin/env bash
# Usage: bash tools/ci/check-rendered-files.sh HOME — fails when a JSON or TOML file that chezmoi rendered into HOME does not parse
set -euo pipefail

home=$1
failed=0
count=0
# Zed reads its JSON files with comments and trailing commas
lenient_json='import json, re, sys
text = re.sub(r"(?m)^\s*//.*$", "", open(sys.argv[1]).read())
json.loads(re.sub(r",(\s*[}\]])", r"\1", text))'

while IFS= read -r file; do
    count=$((count + 1))
    case $file in
        */.config/zed/*) python3 -c "$lenient_json" "$file" 2>/dev/null ;;
        *) jq empty "$file" 2>/dev/null ;;
    esac || { echo "check-rendered-files: $file is not valid JSON" >&2; failed=1; }
done < <(find "$home" -type f -name '*.json')
while IFS= read -r file; do
    count=$((count + 1))
    python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$file" 2>/dev/null ||
        { echo "check-rendered-files: $file is not valid TOML" >&2; failed=1; }
done < <(find "$home" -type f -name '*.toml')
[ "$failed" = 0 ] && echo "check-rendered-files: all $count JSON and TOML files parse"
exit "$failed"
