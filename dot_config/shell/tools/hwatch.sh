case ${DOTFILES_PHASE:-} in
aliases)
    alias-if-exists hwatch watch="hwatch -c -s \"${ZSH_VERSION:+zsh}${BASH_VERSION:+bash} -ic\""
    return 0 ;;
esac
