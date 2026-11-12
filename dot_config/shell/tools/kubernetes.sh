case ${DOTFILES_PHASE:-} in
aliases)
    command -v kubectl >/dev/null 2>&1 || return 0
    alias k='kubectl'
    alias kx='kubectx'
    return 0 ;;
esac
[ -n "${ZSH_VERSION:-}" ] || return 0

case $DOTFILES_PHASE in
setup)
    (( $+commands[kubectl] )) || return 0
    _kubectl_completion() { source <(command kubectl completion zsh) }
    _lazy_completions[kubectl]=_kubectl_completion
    # `k` completes as kubectl: the =form defers to whatever kubectl has bound, so it picks up the lazy stub.
    # kubectx ships _kubectx in site-functions, so compinit already has it.
    _kubernetes_compdefs() {
        compdef k=kubectl
        if (( $+commands[kubectx] )); then
            compdef kx=kubectx
        fi
    }
    _after_compinit+=(_kubernetes_compdefs) ;;
esac
