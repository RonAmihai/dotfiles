case ${DOTFILES_PHASE:-} in
aliases)
    command -v codex-reload >/dev/null 2>&1 && alias codex='codex-reload'
    command -v codex >/dev/null 2>&1 && alias cdx='codex' cdr='codex resume'
    return 0 ;;
esac
[ -n "${ZSH_VERSION:-}" ] || return 0

case $DOTFILES_PHASE in
update)
    [[ $OSTYPE == linux-android* ]] || return 0
    _update_add 30 codex _update_codex
    _update_codex() {
        [[ $mode == update && -e ~/.codex/packages/standalone/current ]] || return 0
        _update_step "Codex CLI" '"$HOME/scripts/codex-setup.sh"'
    } ;;
esac
