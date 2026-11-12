case ${DOTFILES_PHASE:-} in
aliases)
    alias-if-exists dust du='dust'
    return 0 ;;
esac
