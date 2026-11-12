case ${DOTFILES_PHASE:-} in
update)
    _update_add 10 dnf _update_dnf
    _update_dnf() {
        [[ $mode == update && ! -e /run/ostree-booted ]] && (( $+commands[dnf] )) \
            && _update_has_files /etc/yum.repos.d/*.repo(N.) || return 0
        _update_os_ran=1
        _update_step "DNF" '_update_sudo dnf upgrade -y --refresh'
    } ;;
esac
