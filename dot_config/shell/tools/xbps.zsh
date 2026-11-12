case ${DOTFILES_PHASE:-} in
update)
    _update_add 10 xbps _update_xbps
    _update_xbps() {
        [[ $mode == update ]] && (( $+commands[xbps-install] )) \
            && _update_has_files /etc/xbps.d/*.conf(N.) /usr/share/xbps.d/*.conf(N.) || return 0
        _update_os_ran=1
        _update_step "XBPS" '_update_sudo xbps-install -Syu'
    } ;;
esac
