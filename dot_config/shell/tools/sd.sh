case ${DOTFILES_PHASE:-} in
aliases)
    alias-if-exists sd sed='sd'
    return 0 ;;
esac
