case ${DOTFILES_PHASE:-} in
path)
    PATH="$PATH:/usr/local/share/dotnet:$HOME/.dotnet/tools"
    return 0 ;;
env)
    export DOTNET_CLI_TELEMETRY_OPTOUT=1
    return 0 ;;
setup)
    # Tab completion for the dotnet CLI in bash. \r also splits, for Windows output
    if [ -n "${BASH_VERSION:-}" ] && command -v dotnet >/dev/null 2>&1; then
        _dotnet_bash_complete() {
            local cur="${COMP_WORDS[COMP_CWORD]}" IFS=$'\r\n' candidates
            read -d '' -ra candidates < <(dotnet complete --position "$COMP_POINT" "$COMP_LINE" 2>/dev/null)
            read -d '' -ra COMPREPLY < <(compgen -W "${candidates[*]:-}" -- "$cur")
        }
        complete -f -F _dotnet_bash_complete dotnet
    fi ;;
aliases)
    alias dotnet-update-global-tools='dotnet tool update -g --all'
    # macOS dual-arch .NET (Apple Silicon only)
    case ${OSTYPE:-}:${CPUTYPE:-${HOSTTYPE:-}} in
        darwin*:arm64|darwin*:aarch64)
            [ -x /usr/local/share/dotnet/x64/dotnet ] && alias xdotnet='/usr/local/share/dotnet/x64/dotnet'
            alias dotnet-list-sdks='dotnet --list-sdks 2>/dev/null; /usr/local/share/dotnet/x64/dotnet --list-sdks 2>/dev/null'
            ;;
        *)
            alias dotnet-list-sdks='dotnet --list-sdks'
            ;;
    esac
    return 0 ;;
esac
[ -n "${ZSH_VERSION:-}" ] || return 0

case $DOTFILES_PHASE in
setup)
    _dotnet_completion() {
        _dotnet_zsh_complete() { reply=("${(ps:\n:)$(command dotnet complete "$words")}") }
        compctl -K _dotnet_zsh_complete dotnet
    }
    _lazy_completions[dotnet]=_dotnet_completion ;;
update)
    _update_add 30 dotnet _update_dotnet
    [[ $OSTYPE == linux-android* ]] && _update_add 30 dotnet-sdk _update_dotnet_sdk
    _update_dotnet() {
        [[ $mode == update ]] && (( $+commands[dotnet] )) || return 0
        _update_step ".NET Global Tools" 'dotnet tool update -g --all'
    }
    _update_dotnet_sdk() {
        [[ $mode == update ]] && (( $+commands[dotnet] )) || return 0
        _update_step ".NET SDK" 'dotnet --list-sdks | grep -oE "^[0-9]+\.[0-9]+" | sort -u | while read -r channel; do "$HOME/scripts/dotnet-update.sh" "$channel"; done'
    } ;;
esac
