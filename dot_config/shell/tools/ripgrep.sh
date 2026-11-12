case ${DOTFILES_PHASE:-} in
aliases)
    alias-if-exists rg grep='rg'
    return 0 ;;
esac
