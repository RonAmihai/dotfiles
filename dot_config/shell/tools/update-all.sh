case ${DOTFILES_PHASE:-} in
aliases)
    case ${OSTYPE:-} in
        msys*|cygwin*|MINGW*)
            if ! command -v zsh >/dev/null 2>&1; then
                _update_windows_powershell() {
                    local _update_name=$1 _update_command=$2 _update_arg _update_ps=pwsh.exe
                    shift 2
                    for _update_arg in "$@"; do
                        case $_update_arg in
                            --dry-run) _update_command="$_update_command -DryRun" ;;
                            --skip-os-updates) _update_command="$_update_command -SkipOSUpdates" ;;
                            -[A-Z]*) _update_command="$_update_command $_update_arg" ;;
                            *)
                                echo "$_update_name: $_update_arg does not work on Windows. Use --dry-run, --skip-os-updates or a PowerShell switch such as -SkipWSL" >&2
                                return 2 ;;
                        esac
                    done
                    command -v "$_update_ps" >/dev/null 2>&1 || _update_ps=powershell.exe
                    "$_update_ps" -NoLogo -Command "$_update_command"
                }
                update-all() { _update_windows_powershell update-all Update-All "$@"; }
                clean-all() { _update_windows_powershell clean-all Clean-All "$@"; }
            fi ;;
        *)
            if ! command -v zsh >/dev/null 2>&1; then
                _update_needs_zsh() {
                    case ${OSTYPE:-} in
                        linux-android*) echo "$1 needs zsh: pkg install zsh" >&2 ;;
                        *) echo "$1 needs zsh: install it with the system package manager" >&2 ;;
                    esac
                    return 1
                }
                update-all() { _update_needs_zsh update-all; }
                clean-all() { _update_needs_zsh clean-all; }
            fi ;;
    esac
    alias ua='update-all'
    alias ca='clean-all'
    return 0 ;;
esac
