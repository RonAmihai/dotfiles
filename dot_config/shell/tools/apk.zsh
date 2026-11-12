case ${DOTFILES_PHASE:-} in
update)
    _update_add 10 apk _update_apk
    _update_apk() {
        [[ $mode == update && -s /etc/apk/repositories ]] && (( $+commands[apk] )) || return 0
        _update_os_ran=1
        _update_step "APK" '_update_sudo apk upgrade --update-cache'
    } ;;
esac
