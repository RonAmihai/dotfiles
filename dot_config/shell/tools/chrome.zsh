case ${DOTFILES_PHASE:-} in
update)
    _update_add 15 chrome _update_chrome
    # Runs before brew, whose receipt sync then records Chrome's new version, so brew cu does not download it again
    _update_chrome() {
        [[ $mode == update && $OSTYPE == darwin* ]] && (( $+commands[update-chrome] )) || return 0
        _update_step "Google Chrome" 'update-chrome'
    } ;;
esac
