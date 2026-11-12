case ${DOTFILES_PHASE:-} in
aliases)
    command -v agy-reload >/dev/null 2>&1 && alias agy='agy-reload'
    command -v agy >/dev/null 2>&1 && alias agr='agy --continue'
    return 0 ;;
esac
[ -n "${ZSH_VERSION:-}" ] || return 0

case $DOTFILES_PHASE in
update)
    _update_add 30 antigravity _update_antigravity
    _update_antigravity() {
        [[ $mode == update ]] && (( $+commands[agy] )) || return 0
        if [[ $OSTYPE == linux-android* ]]; then
            _update_step "Antigravity CLI" '"$HOME/scripts/agy-setup.sh"'
        else
            _update_step "Antigravity CLI" 'agy update'
        fi
    } ;;
esac
