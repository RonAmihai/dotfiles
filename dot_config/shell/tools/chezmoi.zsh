case ${DOTFILES_PHASE:-} in
update)
    _update_add 90 dotfiles _update_dotfiles
    _update_dotfiles() {
        [[ $mode == update ]] || return 0
        _update_chezmoi "Dotfiles" chezmoi
    } ;;
esac
