case ${DOTFILES_PHASE:-} in
aliases)
    alias-if-exists duf df='duf'
    return 0 ;;
esac
