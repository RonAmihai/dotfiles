case ${DOTFILES_PHASE:-} in
aliases)
    command -v python3 >/dev/null 2>&1 || return 0
    alias python=python3
    alias pip=pip3
    return 0 ;;
esac
