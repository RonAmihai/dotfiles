[ -x /data/data/com.termux/files/usr/bin/pkg ] || return 0
case ${DOTFILES_PHASE:-} in
path)
    PATH="$PATH:$HOME/scripts:$HOME/.dotnet"
    return 0 ;;
env)
    export TMPDIR="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
    # Termux leaves USER unset, and the oh-my-posh prompt reads the user name from it
    export USER="${USER:-${LOGNAME:-$(id -un)}}"
    export DOTNET_ROOT="$HOME/.dotnet"
    export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
    export DOTNET_GCHeapHardLimit=1C0000000
    export DOTNET_gcServer=0
    return 0 ;;
setup)
    # Android stops the Termux:API app when idle, and until something starts it, pbcopy and the termux-* tools wait for it
    if [ -z "${AGENT_SHELL:-}" ] && [ -d /data/data/com.termux.api ] && command -v termux-api-start >/dev/null 2>&1; then
        # sh, not a subshell: a bash subshell keeps bash's fd 255 open, so a caller that reads the shell's output waits
        ( sh -c 'pgrep -x com.termux.api >/dev/null && exit 0
            termux-api-start
            sleep 2
            # An API call is a broadcast, which also wakes an app that never ran, where termux-api-start says "Not found"
            pgrep -x com.termux.api >/dev/null || timeout 30 termux-battery-status' </dev/null >/dev/null 2>&1 & )
    fi
    return 0 ;;
esac
[ -n "${ZSH_VERSION:-}" ] || return 0

case $DOTFILES_PHASE in
update)
    _update_add 10 termux-pkg _update_termux_pkg
    _update_add 30 termux-caches _update_termux_caches

    _update_termux_pkg() {
        if [[ $mode == update ]]; then
            _update_os_ran=1
            _update_step "Termux Packages" 'pkg upgrade -y'
        else
            _update_step "Termux Package Cache" 'pkg clean && apt autoremove -y'
        fi
    }
    # work --end deletes the work profile after its leak report, so the cleanup never touches it
    _update_termux_caches() {
        [[ $mode == clean ]] || return 0
        local -a cmds
        (( $+commands[dotnet] )) && cmds+=('dotnet nuget locals all --clear')
        (( $+commands[npm] )) && cmds+=('npm cache clean --force' 'rm -rf ~/.npm/_npx')
        (( $+commands[pip] )) && cmds+=('pip cache purge')
        (( $+commands[go] )) && cmds+=('go clean -cache -modcache')
        cmds+=("find ${PREFIX:-/data/data/com.termux/files/usr}/tmp -mindepth 1 -maxdepth 1 ! -name work-profile -exec rm -rf {} +")
        _update_step "Termux Caches" "${(j:; :)cmds}"
    } ;;
esac
