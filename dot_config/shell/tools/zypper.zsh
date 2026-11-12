case ${DOTFILES_PHASE:-} in
update)
    _update_add 10 zypper _update_zypper
    _update_zypper() {
        [[ $mode == update ]] && (( $+commands[zypper] )) \
            && _update_has_files /etc/zypp/repos.d/*.repo(N.) || return 0
        _update_os_ran=1
        _update_step "Zypper" '_update_sudo zypper --non-interactive refresh && _update_sudo zypper --non-interactive update'
    } ;;
esac
