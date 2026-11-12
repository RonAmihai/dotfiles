[[ -o interactive && -n "$CMUX_SHELL_INTEGRATION_DIR" ]] || return 0

autoload -Uz add-zsh-hook

# cmux replays the saved screen on relaunch and the replay ends mid-line, so PROMPT_SP would draw a `%` above the first prompt
unsetopt prompt_sp
typeset -g _cmux_prompt_count=0
_cmux_restore_prompt_sp() {
    (( ++_cmux_prompt_count >= 2 )) || return
    setopt prompt_sp
    add-zsh-hook -d precmd _cmux_restore_prompt_sp
    unfunction _cmux_restore_prompt_sp
    unset _cmux_prompt_count
}
add-zsh-hook precmd _cmux_restore_prompt_sp

# cmux 0.65 checks the claude shim folders with ~50 /usr/bin/find runs (manaflow-ai/cmux#21977); the rest stops once cmux drops them
[[ -r $CMUX_SHELL_INTEGRATION_DIR/cmux-zsh-integration.zsh \
    && $(<$CMUX_SHELL_INTEGRATION_DIR/cmux-zsh-integration.zsh) == *'/usr/bin/find -P "$current" -prune'* ]] || return 0

if [[ ${CMUX_CLAUDE_INTEGRATION_DISABLED:-0} != 1 ]]; then
    CMUX_CLAUDE_INTEGRATION_DISABLED=1
    typeset -g _cmux_claude_check_skipped=1
fi

# Registered before cmux's own precmd hooks, so _cmux_fix_path installs the claude shim with this check
_cmux_use_zstat_path_check() {
    add-zsh-hook -d precmd _cmux_use_zstat_path_check
    unfunction _cmux_use_zstat_path_check
    if (( ${+_cmux_claude_check_skipped} )); then
        CMUX_CLAUDE_INTEGRATION_DISABLED=0
        unset _cmux_claude_check_skipped
    fi
    (( $+functions[_cmux_private_path_node] )) || return 0
    zmodload -F zsh/stat b:zstat 2>/dev/null || return 0
    _cmux_private_path_node() {
        builtin emulate -L zsh
        local -A st
        builtin zstat -L -H st -- "$1" 2>/dev/null || return 1
        (( st[uid] == EUID || st[uid] == 0 )) || return 1
        [[ -L $1 ]] && return 0
        [[ -d $1 ]] || return 1
        (( !(st[mode] & 8#022) || (st[mode] & 8#1000) ))
    }
}
add-zsh-hook precmd _cmux_use_zstat_path_check
