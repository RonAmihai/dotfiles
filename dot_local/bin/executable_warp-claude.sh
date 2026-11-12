#!/bin/bash
# warp-claude.sh - Launch Warp with Claude Code on macOS, Linux or Windows (Git Bash)

# Resolve target directory to absolute path
TARGET_DIR="${1:-$(pwd)}"
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
  echo "Error: Cannot access directory '$1'" >&2
  exit 1
}

case "$(uname -s)" in
  Darwin) CONFIG_DIR="$HOME/.warp/launch_configurations" ;;
  Linux)  CONFIG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/warp-terminal/launch_configurations" ;;
  MINGW*|MSYS*|CYGWIN*)
    CONFIG_DIR="$(cygpath -u "$APPDATA")/warp/Warp/data/launch_configurations"
    TARGET_DIR="$(cygpath -w "$TARGET_DIR")" ;;
  *) echo "Error: Unsupported OS '$(uname -s)'" >&2; exit 1 ;;
esac
mkdir -p "$CONFIG_DIR"

# A background cleanup does not survive every launcher, so the next run removes old launch files
find "$CONFIG_DIR" -name 'claude-*.yaml' -mmin +1 -exec rm -f {} + 2>/dev/null

CONFIG_ID="claude-$(date +%s)-$$"
# A single-quoted YAML string keeps the backslashes of a Windows path, and doubles a single quote
YAML_DIR=${TARGET_DIR//\'/\'\'}
cat >"$CONFIG_DIR/${CONFIG_ID}.yaml" <<EOF
name: $CONFIG_ID
windows:
  - tabs:
      - title: Claude Code
        layout:
          cwd: '$YAML_DIR'
          commands:
            - exec: claude --ide
EOF

case "$(uname -s)" in
  Darwin) open "warp://launch/${CONFIG_ID}" ;;
  Linux)  xdg-open "warp://launch/${CONFIG_ID}" ;;
  *)      cmd.exe //c start "" "warp://launch/${CONFIG_ID}" ;;
esac
