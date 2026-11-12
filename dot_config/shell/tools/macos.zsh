case ${DOTFILES_PHASE:-} in
update)
    _update_add 10 macos _update_macos
    _update_macos() {
        [[ $mode == update && $OSTYPE == darwin* ]] || return 0
        _update_os_ran=1
        _update_step "macOS Software Update" 'sudo softwareupdate -i -a'
    } ;;
esac
