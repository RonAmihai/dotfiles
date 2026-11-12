case ${DOTFILES_PHASE:-} in
path)
    # snapd adds /snap/bin through /etc/profile.d, which bash reads and zsh does not
    [ -r /etc/profile.d/apps-bin-path.sh ] && PATH="$PATH:/snap/bin"
    return 0 ;;
esac
[ -n "${ZSH_VERSION:-}" ] || return 0

case $DOTFILES_PHASE in
update)
    _update_add 20 snap _update_snap
    # snap is useless without the snapd service, which WSL and containers often lack
    _update_snap() {
        [[ $mode == update && -S /run/snapd.socket ]] && (( $+commands[snap] )) || return 0
        _update_step "Snap" '_update_sudo snap refresh'
    } ;;
esac
