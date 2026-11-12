case ${DOTFILES_PHASE:-} in
aliases)
    alias-if-exists lazygit lg='lazygit'
    return 0 ;;
esac
