#!/bin/bash
# terminal-hotkey.sh - hand the Ctrl-Cmd-Enter launcher hotkey to cmux or Warp.
#
# Only one app can hold a system-wide hotkey, so this sets both sides at once:
#
#   cmux  shortcuts.bindings.showHideAllWindows  in ~/.config/cmux/cmux.json
#   Warp  [global_hotkey.toggle_all_windows]     in ~/.warp/settings.toml
#
# cmux.json is managed by chezmoi, so the edit goes to the chezmoi source and
# then applies. That leaves the dotfiles repo dirty. Commit when you settle.
#
# cmux picks the change up from `cmux reload-config`. Warp registers its hotkey
# at startup, so Warp must restart before its side takes effect.

set -euo pipefail

HOTKEY_CMUX="ctrl+cmd+enter"
HOTKEY_WARP="ctrl-cmd-enter"

CMUX_TARGET="$HOME/.config/cmux/cmux.json"
WARP_SETTINGS="$HOME/.warp/settings.toml"
CHEZMOI="/opt/homebrew/bin/chezmoi"
CMUX_CLI="/opt/homebrew/bin/cmux"

RESTART_WARP=0

usage() {
  cat <<'USAGE'
Usage: terminal-hotkey.sh [status|cmux|warp] [--restart-warp]

  status          Show which app owns Ctrl-Cmd-Enter (default)
  cmux            Give the hotkey to cmux, take it from Warp
  warp            Give the hotkey to Warp, take it from cmux
  --restart-warp  Quit and reopen Warp so its side takes effect now
  -h, --help      Show this help

Warp only registers or releases the hotkey at startup. Without
--restart-warp the script tells you to relaunch Warp yourself.
USAGE
}

die() { printf 'Error: %s\n' "$1" >&2; exit 1; }

# --- readers -----------------------------------------------------------------

cmux_binding() {
  [ -f "$CMUX_TARGET" ] || { printf '(no cmux.json)'; return; }
  /usr/bin/sed -n 's/.*"showHideAllWindows"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "$CMUX_TARGET" | /usr/bin/head -1
}

# Reads `enabled` from inside [global_hotkey.toggle_all_windows] only. The
# dedicated_window section carries its own `enabled`, so a plain grep is wrong.
warp_enabled() {
  [ -f "$WARP_SETTINGS" ] || { printf '(no settings.toml)'; return; }
  /usr/bin/awk '
    /^\[/ { in_section = ($0 == "[global_hotkey.toggle_all_windows]") }
    in_section && /^enabled[[:space:]]*=/ {
      value = $0
      sub(/^[^=]*=[[:space:]]*/, "", value)
      gsub(/[^a-z]/, "", value)
      print value
      exit
    }
  ' "$WARP_SETTINGS"
}

# --- writers -----------------------------------------------------------------

set_cmux_binding() {
  local value="$1" source_path
  source_path="$("$CHEZMOI" source-path "$CMUX_TARGET" 2>/dev/null || true)"
  [ -n "$source_path" ] && [ -f "$source_path" ] \
    || die "cmux.json is not managed by chezmoi; edit $CMUX_TARGET by hand"
  /usr/bin/grep -q '"showHideAllWindows"' "$source_path" \
    || die "no showHideAllWindows key in $source_path"

  /usr/bin/sed -i '' \
    "s|\(\"showHideAllWindows\"[[:space:]]*:[[:space:]]*\)\"[^\"]*\"|\1\"${value}\"|" \
    "$source_path"
  "$CHEZMOI" apply "$CMUX_TARGET"

  if "$CMUX_CLI" ping >/dev/null 2>&1; then
    "$CMUX_CLI" reload-config >/dev/null && printf '  cmux    reloaded\n'
  else
    printf '  cmux    not running, it reads the file at launch\n'
  fi
}

set_warp_enabled() {
  local value="$1" tmp
  [ -f "$WARP_SETTINGS" ] || die "no $WARP_SETTINGS"
  tmp="$(/usr/bin/mktemp)"
  /usr/bin/awk -v want="$value" '
    /^\[/ { in_section = ($0 == "[global_hotkey.toggle_all_windows]") }
    in_section && /^enabled[[:space:]]*=/ { print "enabled = " want; next }
    { print }
  ' "$WARP_SETTINGS" > "$tmp"
  # Write through the original file rather than mv'ing the temp over it. mktemp
  # makes 0600, and mv would carry that mode onto settings.toml.
  /bin/cat "$tmp" > "$WARP_SETTINGS"
  /bin/rm -f "$tmp"

  if /usr/bin/pgrep -qx stable 2>/dev/null || /usr/bin/pgrep -f '/Warp.app/' >/dev/null 2>&1; then
    if [ "$RESTART_WARP" -eq 1 ]; then
      /usr/bin/osascript -e 'tell application "Warp" to quit' >/dev/null 2>&1 || true
      local i=0
      while /usr/bin/pgrep -f '/Warp.app/' >/dev/null 2>&1 && [ "$i" -lt 20 ]; do
        /bin/sleep 0.25
        i=$((i + 1))
      done
      /usr/bin/open -a Warp
      printf '  Warp    restarted\n'
    else
      printf '  Warp    running, relaunch it or rerun with --restart-warp\n'
    fi
  else
    printf '  Warp    not running, it reads the file at launch\n'
  fi
}

# --- reporting ---------------------------------------------------------------

report() {
  local binding warp owner
  binding="$(cmux_binding)"
  warp="$(warp_enabled)"

  if [ "$binding" = "$HOTKEY_CMUX" ] && [ "$warp" = "true" ]; then
    owner='both claim it, whichever starts first wins'
  elif [ "$binding" = "$HOTKEY_CMUX" ]; then
    owner='cmux'
  elif [ "$warp" = "true" ]; then
    owner='Warp'
  else
    owner='nobody'
  fi

  printf 'Ctrl-Cmd-Enter owner: %s\n' "$owner"
  printf '  cmux  showHideAllWindows          = %s\n' "${binding:-<unset>}"
  printf '  Warp  toggle_all_windows.enabled  = %s (%s)\n' "${warp:-<unset>}" "$HOTKEY_WARP"
}

# --- main --------------------------------------------------------------------

MODE=status
for arg in "$@"; do
  case "$arg" in
    status|cmux|warp) MODE="$arg" ;;
    --restart-warp)   RESTART_WARP=1 ;;
    -h|--help)        usage; exit 0 ;;
    *)                printf 'Unknown argument: %s\n\n' "$arg" >&2; usage >&2; exit 1 ;;
  esac
done

case "$MODE" in
  status)
    report
    ;;
  cmux)
    printf 'Giving Ctrl-Cmd-Enter to cmux.\n'
    set_warp_enabled false
    set_cmux_binding "$HOTKEY_CMUX"
    printf '\n'
    report
    ;;
  warp)
    printf 'Giving Ctrl-Cmd-Enter to Warp.\n'
    set_cmux_binding none
    set_warp_enabled true
    printf '\n'
    report
    ;;
esac
