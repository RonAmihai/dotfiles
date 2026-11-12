case ${DOTFILES_PHASE:-} in
update)
    _update_add 10 rpm-ostree _update_rpm-ostree
    # Image-based Fedora (Silverblue, Kinoite, Bazzite): only rpm-ostree may change the system, so dnf.zsh and yum.zsh skip
    _update_rpm-ostree() {
        [[ $mode == update && -e /run/ostree-booted ]] && (( $+commands[rpm-ostree] )) || return 0
        _update_os_ran=1
        _update_step "rpm-ostree" '_update_sudo rpm-ostree upgrade'
    } ;;
esac
