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
            "$layer" "$subcommand" "$@" || return
        done
        echo "== chezmoi"
        chezmoi "$subcommand" "$@"
    }
    # exec would leave an agent's shell, which has no terminal, waiting for input, and orphan background jobs, so those get a hint
    _chezmoi_reload_if_changed() {
        local marker=$1 home=${DOTFILES_HOME:-$HOME} changed jobs_count
        changed=$(find "$home/.zshrc" "$home/.zshenv" "$home/.personal.zsh" "$home/.bashrc" "$home/.bash_profile" \
            "$home/.config/shell" -newer "$marker" 2>/dev/null | head -n 1)
        rm -f "$marker"
        [ -n "$changed" ] || return 0
        if [ -n "${ZSH_VERSION:-}" ]; then
            zmodload zsh/parameter 2>/dev/null
            jobs_count=${#jobstates}
        else
            jobs_count=$(jobs -p | wc -l)
        fi
        if [ -n "${AGENT_SHELL:-}" ] || [ ! -t 0 ] || [ ! -t 1 ]; then
            echo "The shell config changed: run reload, or open a new terminal, to load it"
        elif [ "$jobs_count" -gt 0 ]; then
            echo "The shell config changed: run reload when your background jobs end"
        else
            echo "The shell config changed, so the shell reloads"
            if [ -n "${ZSH_VERSION:-}" ]; then exec zsh; else exec bash; fi
        fi
    }
    _chezmoi_layers_then_reload() {
        local marker rc
        marker=$(mktemp)
        _chezmoi_layers "$@"
        rc=$?
        _chezmoi_reload_if_changed "$marker"
        return $rc
    }
    cza() { _chezmoi_layers_then_reload apply "$@"; }
    czs() { _chezmoi_layers status "$@"; }
    czd() { _chezmoi_layers diff "$@"; }
    czu() { _chezmoi_layers_then_reload update "$@"; }
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
