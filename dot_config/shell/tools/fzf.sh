case ${DOTFILES_PHASE:-} in
env)
    # Debian and Ubuntu install fd as fdfind
    _fd=fd
    if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
        _fd=fdfind
    fi
    export FZF_DEFAULT_COMMAND="$_fd --type f --hidden --exclude .git"
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND="$_fd --type d --hidden --exclude .git"
    unset _fd
    export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --preview "bat --color=always --style=numbers --line-range=:500 {} 2>/dev/null || eza --icons --group-directories-first {}"'
    return 0 ;;
late)
    # Late, because fzf wraps the completions that other tools set up, such as zoxide's for cd
    if [ -n "${BASH_VERSION:-}" ] && [ -z "${AGENT_SHELL:-}" ]; then
        _bashrc_cached_init fzf fzf --bash || { [ -r ~/.fzf.bash ] && . ~/.fzf.bash; }
    fi
    return 0 ;;
esac
[ -n "${ZSH_VERSION:-}" ] || return 0

case $DOTFILES_PHASE in
setup)
    _fzf_completion() { [[ -f ~/.fzf.zsh ]] && source ~/.fzf.zsh }
    _lazy_completions[fzf]=_fzf_completion
    # fzf-tab must load after compinit, which the wait"0" plugins run
    [[ -z $AGENT_SHELL ]] && (( $+functions[zinit] )) && zinit wait"1" lucid light-mode for Aloxaf/fzf-tab ;;
esac
