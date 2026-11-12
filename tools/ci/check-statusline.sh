#!/usr/bin/env bash
# Usage: bash tools/ci/check-statusline.sh — runs agent-statusline with sample Claude Code and agy input, and fails on an error or a missing part
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
script="$repo/dot_local/bin/executable_agent-statusline"

fail() { echo "check-statusline: $*" >&2; exit 1; }
expect() {
    case $2 in
        *"$3"*) ;;
        *) fail "$1: the output has no \"$3\": $2" ;;
    esac
}
lines() { printf '%s\n' "$1" | wc -l | tr -d ' '; }

claude='{"model":{"display_name":"Sample Opus"},"effort":{"level":"high"},"context_window":{"used_percentage":31},
"cost":{"total_cost_usd":1.5},"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":1893456000},
"seven_day":{"used_percentage":12,"resets_at":1893888000}},"worktree":{"original_cwd":"'"$repo"'"}}'
out=$(printf '%s' "$claude" | STATUSLINE_WIDTH=200 python3 "$script")
for part in 'Sample Opus' high '31%' '$1.50' 5h 7d; do expect claude "$out" "$part"; done
[ "$(lines "$out")" = 2 ] || fail "claude: expected two lines: $out"

out=$(printf '%s' "$claude" | STATUSLINE_WIDTH=40 python3 "$script")
[ "$(lines "$out")" = 2 ] || fail "claude, narrow: expected two lines: $out"

home_session=$(printf '%s' "$claude" | sed "s|\"original_cwd\":\"$repo\"|\"original_cwd\":\"$HOME\"|")
out=$(printf '%s' "$home_session" | STATUSLINE_WIDTH=40 python3 "$script")
expect "claude, narrow, in the home folder" "$out" "📁 ~"

agy='{"cwd":"'"$repo"'","model":{"display_name":"Gemini 3.1 Pro (High)","effort":"high"},
"context_window":{"used_percentage":42.4},"terminal_width":200,
"quota":{"gemini-5h":{"remaining_fraction":0.25,"reset_time":"2030-01-01T03:30:00Z"},
"gemini-weekly":{"remaining_fraction":0.5,"reset_time":"2030-01-05T14:15:00Z"}}}'
out=$(printf '%s' "$agy" | python3 "$script" --agy)
for part in 'Gemini 3.1 Pro' high '42%' '75%' '50%' 5h 7d; do expect agy "$out" "$part"; done
case $out in *'(High)'*) fail "agy: the effort shows twice: $out" ;; esac

printf '{}' | python3 "$script" > /dev/null || fail "empty input: the script failed"

echo "check-statusline: Claude Code and agy input render"
