#!/bin/bash
# cmux-claude.sh - Launch Claude Code in a cmux workspace
#
# Usage: cmux-claude.sh [--agent-session] [directory]
#
# By default opens a terminal workspace running `claude --ide`, matching
# warp-claude.sh. With --agent-session, opens cmux's
# native agent surface instead (its own chat UI, not the Claude Code CLI).

set -u

# Silence cmux's legacy-alias deprecation notices
export CMUX_QUIET=1

usage() {
  cat <<'USAGE'
Usage: cmux-claude.sh [--agent-session] [directory]

  directory         Working directory (default: current directory)
  --agent-session   Use cmux's native agent surface instead of `claude --ide`
  -h, --help        Show this help
USAGE
}

AGENT_SESSION=0
TARGET_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --agent-session) AGENT_SESSION=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    --)              shift; TARGET_ARG="${1:-}"; break ;;
    -*)              echo "Error: Unknown option '$1'" >&2; usage >&2; exit 1 ;;
    *)               TARGET_ARG="$1"; shift ;;
  esac
done

# Resolve target directory to absolute path
TARGET_DIR="${TARGET_ARG:-$(pwd)}"
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
  echo "Error: Cannot access directory '$TARGET_ARG'" >&2
  exit 1
}

command -v cmux >/dev/null 2>&1 || {
  echo "Error: cmux CLI not found in PATH" >&2
  exit 1
}

# cmux is driven over a Unix socket, so the app must be running first
if ! cmux ping >/dev/null 2>&1; then
  case "$(uname)" in
    Darwin) open -a cmux ;;
    *)      echo "Error: cmux is not running (auto-launch is macOS-only)" >&2; exit 1 ;;
  esac
  for _ in $(seq 1 30); do
    cmux ping >/dev/null 2>&1 && break
    sleep 0.5
  done
  cmux ping >/dev/null 2>&1 || {
    echo "Error: cmux did not become ready within 15s" >&2
    exit 1
  }
fi

if [ "$AGENT_SESSION" -eq 1 ]; then
  # Create the workspace, then add a native agent surface to it
  CREATED="$(cmux workspace create --name "Claude Code" --cwd "$TARGET_DIR" --focus true)" || exit 1
  WORKSPACE="${CREATED##* }"
  case "$WORKSPACE" in
    workspace:*|[0-9A-Fa-f]*-*) ;;
    *) echo "Error: Could not parse workspace from: $CREATED" >&2; exit 1 ;;
  esac
  cmux new-surface --type agent-session --provider claude \
    --workspace "$WORKSPACE" --working-directory "$TARGET_DIR" --focus true || exit 1
else
  cmux workspace create --name "Claude Code" --cwd "$TARGET_DIR" \
    --command "claude --ide" --focus true || exit 1
fi

# Raise cmux so the new workspace is actually visible
[ "$(uname)" = "Darwin" ] && open -a cmux

exit 0
