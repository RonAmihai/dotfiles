case ${DOTFILES_PHASE:-} in
update)
    _update_add 20 nix _update_nix
    _update_nix() {
        [[ $mode == update ]] || return 0
        # A Nix user profile is either a `nix profile` (manifest.json) or an older nix-env profile (manifest.nix)
        if [[ -e ~/.nix-profile/manifest.json ]] && (( $+commands[nix] )); then
            _update_step "Nix Profile" "nix profile upgrade --all 2>/dev/null || nix profile upgrade '.*'"
        elif [[ -e ~/.nix-profile/manifest.nix ]] && (( $+commands[nix-env] )); then
            _update_step "Nix Profile" 'nix-channel --update && nix-env --upgrade'
        fi
    } ;;
esac
