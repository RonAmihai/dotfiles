case ${DOTFILES_PHASE:-} in
update)
    _update_add 10 apt _update_apt
    _update_apt() {
        # Termux's pkg step owns these packages, and inside termux-chroot /etc/apt is Termux's
        [[ $OSTYPE == linux-android* ]] && return 0
        [[ $mode == update ]] && (( $+commands[apt-get] )) \
            && _update_has_files /etc/apt/sources.list(N.L+0) /etc/apt/sources.list.d/*.(list|sources)(N.) || return 0
        _update_os_ran=1
        _update_step "APT" '_update_sudo apt-get update && _update_sudo apt-get upgrade -y'
    } ;;
esac
