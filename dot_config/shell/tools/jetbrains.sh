case ${DOTFILES_PHASE:-} in
env)
    # Clear the JetBrains terminal marker when not actually inside JetBrains
    if [ "${TERMINAL_EMULATOR:-}" = JetBrains-JediTerm ] && [ -z "${JEDITERM_SOURCE:-}" ]; then
        unset TERMINAL_EMULATOR
    fi
    return 0 ;;
esac
