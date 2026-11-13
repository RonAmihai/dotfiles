case ${DOTFILES_PHASE:-} in
aliases)
    alias czm='chezmoi'
    alias cze='chezmoi edit'
    # Runs a chezmoi command in each dotfiles layer, then in the public repo, so its templates read the layers' data
    _chezmoi_layers() {
        local subcommand=$1 layer
        shift
        [ -n "${ZSH_VERSION:-}" ] && setopt localoptions nullglob
        for layer in "$HOME"/.local/bin/chezmoi-*; do
            [ -x "$layer" ] || continue
            echo "== ${layer##*/}"
            "$layer" "$subcommand" || return
        done
        echo "== chezmoi"
        chezmoi "$subcommand" "$@"
    }
    cza() { _chezmoi_layers apply "$@"; }
    czs() { _chezmoi_layers status "$@"; }
    czd() { _chezmoi_layers diff "$@"; }
    czu() { _chezmoi_layers update "$@"; }
    czcd() { cd "$(chezmoi source-path)" || return; }
    return 0 ;;
esac
[ -n "${ZSH_VERSION:-}" ] || return 0

case $DOTFILES_PHASE in
update)
    _update_add 90 dotfiles _update_dotfiles
    _update_dotfiles() {
        [[ $mode == update ]] || return 0
        _update_chezmoi "Dotfiles" chezmoi
    } ;;
esac
