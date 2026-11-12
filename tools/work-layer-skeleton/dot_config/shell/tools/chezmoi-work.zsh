case ${DOTFILES_PHASE:-} in
update)
    _update_add 91 work-dotfiles _update_work_dotfiles
    _update_work_dotfiles() {
        [[ $mode == update ]] || return 0
        _update_chezmoi "Work dotfiles" chezmoi-work
    } ;;
esac
