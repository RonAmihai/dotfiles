case ${DOTFILES_PHASE:-} in
aliases)
    alias opc='opencode'
    alias opcc='opencode --continue'
    # Picks a session of this project to resume; without fzf and jq it continues the last one
    opr() {
        if ! command -v fzf >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
            opencode --continue "$@"
            return
        fi
        local id
        id=$(opencode session list --format json |
            jq -r '.[] | [.id, (.updated / 1000 | strflocaltime("%d/%m %H:%M")), (.title // "untitled")] | @tsv' |
            fzf --delimiter='\t' --with-nth=2.. --prompt='session> ' | cut -f1) || return
        [ -n "$id" ] && opencode --session "$id" "$@"
    }
    return 0 ;;
esac
[ -n "${ZSH_VERSION:-}" ] || return 0

case $DOTFILES_PHASE in
update)
    _update_add 30 opencode _update_opencode
    _update_opencode() {
        [[ $mode == update ]] && (( $+commands[opencode] )) || return 0
        _update_step "opencode Plugins" 'opencode plugin update'
    }
    ;;
esac
