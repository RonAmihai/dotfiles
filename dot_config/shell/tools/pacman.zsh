case ${DOTFILES_PHASE:-} in
update)
    _update_add 10 pacman _update_pacman
    _update_pacman() {
        [[ $mode == update && -r /etc/pacman.conf ]] && (( $+commands[pacman] )) || return 0
        local -a pacman_repos=(${${(M)${(f)"$(</etc/pacman.conf)"}:#\[*\]}:#\[options\]})
        (( ${#pacman_repos} )) || return 0
        _update_os_ran=1
        # paru and yay also update AUR packages; they call sudo themselves and refuse to run as root
        if (( EUID != 0 && $+commands[paru] )); then
            _update_step "paru: pacman + AUR" 'paru -Syu --noconfirm'
        elif (( EUID != 0 && $+commands[yay] )); then
            _update_step "yay: pacman + AUR" 'yay -Syu --noconfirm'
        else
            _update_step "pacman" '_update_sudo pacman -Syu --noconfirm'
        fi
    } ;;
esac
