case ${DOTFILES_PHASE:-} in
env)
    export DOCKER_SCAN_SUGGEST=false
    return 0 ;;
aliases)
    command -v docker >/dev/null 2>&1 || return 0
    alias docker-x64='DOCKER_DEFAULT_PLATFORM=linux/amd64 docker'
    alias clear-docker='docker container prune -f'
    alias dcp='docker-compose ps'
    return 0 ;;
esac
[ -n "${ZSH_VERSION:-}" ] || return 0

case $DOTFILES_PHASE in
setup)
    _docker_completion() { source <(command docker completion zsh) }
    _lazy_completions[docker]=_docker_completion ;;
esac
