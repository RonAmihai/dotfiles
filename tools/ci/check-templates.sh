#!/usr/bin/env bash
# Usage: bash tools/ci/check-templates.sh CHEZMOI CONFIG — renders the modify templates with sample files and the Windows install scripts, and fails on a wrong or unstable result
set -euo pipefail

cm=$1
config=$2
repo=$(cd "$(dirname "$0")/../.." && pwd)
fixtures="$repo/tools/ci/fixtures"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { echo "check-templates: $*" >&2; exit 1; }

# Renders a modify template twice and keeps both results, so a check can compare them
render_twice() {
    local template=$1 input=$2 name=$3 data=${4:-'{}'}
    "$cm" --config "$config" --source "$repo" execute-template --override-data "$data" --with-stdin "$(cat "$repo/$template")" \
        < "$input" > "$tmp/$name.once"
    "$cm" --config "$config" --source "$repo" execute-template --override-data "$data" --with-stdin "$(cat "$repo/$template")" \
        < "$tmp/$name.once" > "$tmp/$name.twice"
    cmp -s "$tmp/$name.once" "$tmp/$name.twice" || fail "$template changes its own output on a second apply"
}

# The sandbox depends on the OS, so both renders name one, and the result is the same on every machine that runs this
render_twice dot_codex/modify_private_config.toml "$fixtures/codex-config.toml" codex '{"chezmoi":{"os":"linux"}}'
render_twice dot_codex/modify_private_config.toml "$fixtures/codex-config.toml" codex-android '{"chezmoi":{"os":"android"}}'
python3 - "$tmp/codex-android.once" <<'PY' || fail "dot_codex/modify_private_config.toml did not turn off the sandbox and the update check on Android"
import sys, tomllib
config = tomllib.load(open(sys.argv[1], "rb"))
assert config["sandbox_mode"] == "danger-full-access"
assert config["approval_policy"] == "on-request"
assert config["approvals_reviewer"] == "auto_review"
assert config["check_for_update_on_startup"] is False
PY
python3 - "$tmp/codex.once" <<'PY' || fail "dot_codex/modify_private_config.toml rendered a wrong config.toml"
import sys, tomllib
config = tomllib.load(open(sys.argv[1], "rb"))
assert config["model"] == "sample-model"
assert config["approval_policy"] == "on-request"
assert config["sandbox_mode"] == "workspace-write"
assert config["approvals_reviewer"] == "auto_review"
assert "check_for_update_on_startup" not in config
assert config["developer_instructions"].strip() == "Sample sandbox instructions."
assert "developer_instructions" not in config["mcp_servers"]["sample"]
assert "context7" in config["mcp_servers"]
assert config["plugins"]["sample@market"]["enabled"] is True
assert config["tui"]["screen_reader_detection_done"] is True
assert config["tui"]["status_line"]
PY

render_twice dot_config/opencode/modify_opencode.json "$fixtures/opencode.json" opencode
jq -e '
    .mcp.servers.sample.type == "local"
    and .mcp.servers.context7.type == "remote"
    and (.plugins | index("sample-plugin") != null)
    and (.plugins | map(select(startswith("superpowers@"))) | length == 1)
    and (.permissions | map(select(.resource == "ls *" and .effect == "allow")) | length == 1)
    and ([.permissions[] | select(.effect == "ask") | .resource] | sort == ["git commit *", "git push *", "rm -rf *"])
' "$tmp/opencode.once" > /dev/null || fail "dot_config/opencode/modify_opencode.json rendered a wrong opencode.json"

render_twice dot_gemini/antigravity-cli/modify_private_settings.json "$fixtures/agy-settings.json" agy
jq -e '
    .model == "sample-model"
    and .trustedWorkspaces == ["/sample"]
    and .altScreenMode == "always"
    and .statusLine.type == "command"
    and (.statusLine.command | endswith("agent-statusline --agy"))
' "$tmp/agy.once" > /dev/null || fail "dot_gemini/antigravity-cli/modify_private_settings.json rendered wrong agy settings"

# Warp's settings sync owns an existing file, so chezmoi may only add the Windows startup shell
warp_render() {
    "$cm" --config "$config" --source "$repo" execute-template --override-data "{\"chezmoi\":{\"os\":\"$1\"}}" \
        --with-stdin "$(cat "$repo/dot_warp/modify_settings.toml")" < "$2" > "$3"
}
for os in darwin linux; do
    warp_render "$os" "$fixtures/warp-settings.toml" "$tmp/warp-$os"
    cmp -s "$fixtures/warp-settings.toml" "$tmp/warp-$os" || fail "the Warp template changed an existing $os file"
done
warp_render windows "$fixtures/warp-settings.toml" "$tmp/warp-windows"
warp_render windows "$tmp/warp-windows" "$tmp/warp-windows.twice"
cmp -s "$tmp/warp-windows" "$tmp/warp-windows.twice" || fail "the Warp template changes its own Windows output on a second apply"
grep -v -e '^startup_shell_override = "pwsh"$' -e '^new_session_shell_override = ' "$tmp/warp-windows" |
    cmp -s - "$fixtures/warp-settings.toml" || fail "the Warp template changed more than the startup shell in an existing Windows file"
grep -v -e '^\[session\]$' -e '^honor_ps1' "$fixtures/warp-settings.toml" > "$tmp/warp-no-session"
warp_render windows "$tmp/warp-no-session" "$tmp/warp-no-session.out"
grep -qx 'startup_shell_override = "pwsh"' "$tmp/warp-no-session.out" || fail "the Warp template did not add the startup shell to a Windows file without [session]"
: > "$tmp/warp-empty"
warp_render darwin "$tmp/warp-empty" "$tmp/warp-new-darwin"
warp_render windows "$tmp/warp-empty" "$tmp/warp-new-windows"
hotkey() { awk '/^\[global_hotkey.toggle_all_windows\]$/{found=1; next} /^\[/{found=0} found && NF' "$1" | tr '\n' ' '; }
[ "$(hotkey "$tmp/warp-new-darwin")" = 'enabled = false keybinding = "ctrl-cmd-enter" ' ] || fail "a new macOS Warp file does not leave the terminal hotkey to cmux"
[ "$(hotkey "$tmp/warp-new-windows")" = 'enabled = true keybinding = "ctrl-alt-enter" ' ] || fail "a new Windows Warp file does not take the terminal hotkey"
grep -qx 'startup_shell_override = "pwsh"' "$tmp/warp-new-windows" || fail "a new Windows Warp file does not start PowerShell"

# chezmoi runs a run_onchange script again only when its rendered text changes
for script in scoop-packages winget-packages install-font; do
    template="$repo/.chezmoiscripts/run_onchange_after_$script.ps1.tmpl"
    without=$(env -u CI -u DOTFILES_INSTALL_PACKAGES "$cm" --config "$config" --source "$repo" \
        execute-template --override-data '{"chezmoi":{"os":"windows"}}' --file "$template")
    with=$(env -u CI DOTFILES_INSTALL_PACKAGES=1 "$cm" --config "$config" --source "$repo" \
        execute-template --override-data '{"chezmoi":{"os":"windows"}}' --file "$template")
    [ -n "$without" ] || fail "$script renders empty for Windows"
    [ "$without" != "$with" ] || fail "$script renders the same text with DOTFILES_INSTALL_PACKAGES=1, so chezmoi would not run it again"
done

echo "check-templates: all templates passed"
