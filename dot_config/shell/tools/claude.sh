case ${DOTFILES_PHASE:-} in
aliases)
    command -v claude-reload >/dev/null 2>&1 && alias claude='claude-reload'
    alias cco='claude --ide'
    alias ccr='claude --ide --resume'
    return 0 ;;
esac
[ -n "${ZSH_VERSION:-}" ] || return 0

case $DOTFILES_PHASE in
update)
    _update_add 30 claude _update_claude
    [[ $OSTYPE == linux-android* ]] && _update_add 30 claude-code _update_claude_code

    _update_claude_code() {
        [[ $mode == update && -e ~/.local/share/claude/claude-native ]] || return 0
        _update_step "Claude Code" '"$HOME/scripts/claude-setup.sh"'
    }

    _progress_bar() {
        local current=$1 total=$2 label=$3 width=30
        local pct=$((current * 100 / total))
        local filled=$((current * width / total))
        local empty=$((width - filled))
        local bar="" rest=""
        repeat $filled bar+="█"
        repeat $empty rest+="░"
        printf '\r\033[2K  %s%s %d%% (%d/%d) %s' "$bar" "$rest" "$pct" "$current" "$total" "$label"
    }

    _update_claude_plugins() {
        local plugins_json="$HOME/.claude/plugins/installed_plugins.json"
        local cache_dir="$HOME/.claude/plugins/cache"
        local plugins=("${(@u)${(@f)$(claude plugin list 2>/dev/null | grep -oE '[^[:space:]]+@[^[:space:]]+')}}")
        if [[ -z "${plugins[1]}" ]]; then
            printf '\033[0;90m  No plugins installed\033[0m\n'
            return 0
        fi
        printf '  Plugins: %s\n' "${(j:, :)plugins}"

        # Clear plugin cache before update to force fresh install
        # (workaround: claude plugin update doesn't refresh cached files)
        _clear_claude_plugin_cache() {
            [[ -f "$plugins_json" ]] || return
            for p in "${plugins[@]}"; do
                local install_path=$(jq -r --arg p "$p" '.plugins[$p][0].installPath // empty' "$plugins_json")
                [[ -n "$install_path" && -d "${install_path:h}" ]] && rm -rf "${install_path:h}"
            done
        }

        _clear_claude_plugin_cache

        local total=${#plugins[@]} current=0 failed=0 start=$SECONDS
        for p in "${plugins[@]}"; do
            _progress_bar $current $total "$p"
            if output=$(claude plugin update "$p" 2>&1); then
                ((current++))
            else
                ((current++)); ((failed++))
            fi
        done
        _progress_bar $current $total ""
        printf '\n'

        # Remove stale version dirs, keeping only the newly installed one
        if [[ -f "$plugins_json" ]]; then
            for p in "${plugins[@]}"; do
                local install_path=$(jq -r --arg p "$p" '.plugins[$p][0].installPath // empty' "$plugins_json")
                if [[ -n "$install_path" && -d "${install_path:h}" ]]; then
                    for version_dir in "${install_path:h}"/*/; do
                        [[ "$version_dir" == "$install_path/" ]] && continue
                        rm -rf "$version_dir"
                    done
                fi
            done
        fi

        # Clean up leftover temp_git directories
        local temp_cleared=0
        for temp_dir in "$cache_dir"/temp_git_*(N/); do
            [[ -d "$temp_dir" ]] || continue
            rm -rf "$temp_dir"
            ((temp_cleared++))
        done
        (( temp_cleared > 0 )) && printf '\033[0;90m  Cleaned %d temp cache(s)\033[0m\n' "$temp_cleared"

        # Clear install counts cache so UI reflects updated versions
        rm -f "$HOME/.claude/plugins/install-counts-cache.json"

        local elapsed=$((SECONDS - start))
        if [[ $failed -eq 0 ]]; then
            printf '\033[1;32m  ✓ %d plugins updated (%ds)\033[0m\n' "$total" "$elapsed"
        else
            printf '\033[1;31m  ✗ %d/%d plugins failed (%ds)\033[0m\n' "$failed" "$total" "$elapsed"
        fi
        return $failed
    }

    _update_claude() {
        [[ $mode == update ]] && (( $+commands[claude] )) || return 0
        _update_step "Claude Code Plugins" '_update_claude_plugins'
    } ;;
esac
