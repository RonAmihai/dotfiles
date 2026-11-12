case ${DOTFILES_PHASE:-} in
aliases)
    alias ff='fastfetch'
    alias nf='neofetch'
    alias-if-exists fastfetch neofetch='fastfetch'
    return 0 ;;
esac
