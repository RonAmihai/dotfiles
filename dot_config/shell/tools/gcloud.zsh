case ${DOTFILES_PHASE:-} in
setup)
    _gcloud_completion() {
        local sdk="$HOMEBREW_PREFIX/share/google-cloud-sdk"
        [[ -f "$sdk/path.zsh.inc" ]] && source "$sdk/path.zsh.inc"
        [[ -f "$sdk/completion.zsh.inc" ]] && source "$sdk/completion.zsh.inc"
    }
    _lazy_completions[gcloud]=_gcloud_completion
    _lazy_completions[gsutil]=_gcloud_completion
    _lazy_completions[bq]=_gcloud_completion ;;
update)
    _update_add 30 gcloud _update_gcloud
    _update_gcloud() {
        [[ $mode == update ]] && (( $+commands[gcloud] )) || return 0
        _update_step "Google Cloud SDK" 'gcloud components update --quiet'
    } ;;
esac
