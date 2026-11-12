case ${DOTFILES_PHASE:-} in
update)
    _update_add 20 flatpak _update_flatpak
    _update_flatpak() {
        [[ $mode == update ]] && (( $+commands[flatpak] )) || return 0
        _update_step "Flatpak" 'flatpak update -y --noninteractive'
    } ;;
esac
