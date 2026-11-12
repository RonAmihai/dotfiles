case ${DOTFILES_PHASE:-} in
env)
    if [ -z "${GPG_TTY:-}" ]; then
        if [ -n "${TTY:-}" ]; then
            GPG_TTY=$TTY
        elif [ -n "${BASH_VERSION:-}" ] && { [ "${BASH_VERSINFO[0]}" -ge 5 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 4 ]; }; }; then
            # bash has no $TTY, so read the terminal from the prompt escape \l instead of running tty (bash 4.4 and later)
            _gpg_tty='\l'
            _gpg_tty=${_gpg_tty@P}
            if [ -e "/dev/pts/$_gpg_tty" ]; then
                GPG_TTY="/dev/pts/$_gpg_tty"
            else
                GPG_TTY="/dev/$_gpg_tty"
            fi
            unset _gpg_tty
        else
            GPG_TTY=$(tty)
        fi
    fi
    export GPG_TTY
    return 0 ;;
aliases)
    case ${OSTYPE:-} in
        darwin*) alias pinentry='pinentry-mac' ;;
    esac
    return 0 ;;
esac
