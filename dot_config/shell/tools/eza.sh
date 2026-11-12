case ${DOTFILES_PHASE:-} in
aliases)
    alias-if-exists eza ls='eza --icons --group-directories-first'
    alias-if-exists eza ll='ls -lah --header --git'
    alias-if-exists eza la='ls -a'
    alias-if-exists eza lt='ls -T -L 2'
    command -v eza >/dev/null 2>&1 || alias ll='ls -la'
    return 0 ;;
esac
