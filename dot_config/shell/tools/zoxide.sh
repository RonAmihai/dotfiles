case ${DOTFILES_PHASE:-} in
setup)
    # Skip in agent shells: zoxide's cd breaks their Bash tool
    if [ -n "${BASH_VERSION:-}" ] && [ -z "${AGENT_SHELL:-}" ]; then
        _bashrc_cached_init zoxide zoxide init bash --cmd cd
    fi ;;
esac
[ -n "${ZSH_VERSION:-}" ] || return 0

case $DOTFILES_PHASE in
setup)
    (( $+commands[zoxide] )) || return 0
    # Cached like the oh-my-posh init: `zoxide init` would be one more process per shell, and every exec pays
    # the inspection latency of endpoint security tools. The cache is rebuilt when the zoxide
    # binary is newer than it.
    if [[ -z "$AGENT_SHELL" ]]; then
        () {
            local _zoxide_cache="${DOTFILES_HOME:-$HOME}/.cache/zsh/zoxide-init.zsh"
            if [[ ! -s $_zoxide_cache ]] || [[ ${commands[zoxide]} -nt $_zoxide_cache ]]; then
                mkdir -p "${_zoxide_cache:h}"
                zoxide init zsh --cmd cd > "$_zoxide_cache" 2>/dev/null
                zcompile -R -- "$_zoxide_cache" 2>/dev/null
            fi
            [[ -s $_zoxide_cache ]] && source "$_zoxide_cache"
        }
    fi ;;
esac
