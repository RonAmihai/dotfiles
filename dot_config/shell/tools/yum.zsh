case ${DOTFILES_PHASE:-} in
update)
    _update_add 10 yum _update_yum
    # Where dnf exists, yum is dnf under another name or manages the same rpm database, so dnf.zsh covers it
    _update_yum() {
        [[ $mode == update && ! -e /run/ostree-booted ]] && (( $+commands[yum] && ! $+commands[dnf] )) \
            && _update_has_files /etc/yum.repos.d/*.repo(N.) || return 0
        _update_os_ran=1
        _update_step "YUM" '_update_sudo yum update -y'
    } ;;
esac
