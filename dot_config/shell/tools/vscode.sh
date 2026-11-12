case ${DOTFILES_PHASE:-} in
env)
    # The editor for git and other tools: VS Code when installed, else vi
    if command -v code >/dev/null 2>&1; then
        export EDITOR='code --wait'
    else
        export EDITOR=vi
    fi
    export VISUAL="$EDITOR"
    return 0 ;;
esac
