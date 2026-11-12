case ${DOTFILES_PHASE:-} in
path)
    case ${OSTYPE:-} in
        msys*|cygwin*|MINGW*)
            for _windows_path in \
                "$HOME/AppData/Local/agy/bin" \
                "$HOME/AppData/Roaming/npm" \
                "$HOME/scoop/shims"; do
                [ -d "$_windows_path" ] && PATH="$_windows_path:$PATH"
            done
            unset _windows_path ;;
    esac
    return 0 ;;
esac
[ -n "${ZSH_VERSION:-}" ] || return 0

case $DOTFILES_PHASE in
update)
    case ${OSTYPE:-} in
        msys*|cygwin*|MINGW*)
            _update_add 10 windows-system _update_windows_system
            _update_add 20 windows-packages _update_windows_packages

            _update_windows_ps() {
                local ps=pwsh.exe
                (( $+commands[$ps] )) || ps=powershell.exe
                (( $+commands[$ps] )) || return 0
                "$ps" -NoLogo -Command "$1"
            }
            _update_windows_system() {
                [[ $mode == update ]] || return 0
                _update_step "Windows and Drivers" \
                    '_update_windows_ps "Update-All -WindowsSystemOnly"'
            }
            _update_windows_packages() {
                if [[ $mode == update ]]; then
                    _update_step "Windows Packages" \
                        '_update_windows_ps "Update-All -NativePackagesOnly"'
                else
                    _update_step "Windows Package Caches" \
                        '_update_windows_ps "Clean-All -NativeOnly"'
                fi
            } ;;
    esac ;;
esac
