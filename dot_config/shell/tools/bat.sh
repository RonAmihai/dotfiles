case ${DOTFILES_PHASE:-} in
aliases)
    # Debian and Ubuntu install bat as batcat
    alias-if-exists batcat cat='batcat --paging=never'
    alias-if-exists bat cat='bat --paging=never'
    return 0 ;;
esac
