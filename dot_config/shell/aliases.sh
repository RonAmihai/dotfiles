# Aliases and small helpers for interactive zsh and bash. POSIX syntax only.
# Each tool's own aliases live in its file in ~/.config/shell/tools.

# System
alias cls='clear'
alias rr='refresh'
alias refresh='reload'
if [ -n "${ZSH_VERSION:-}" ]; then
    alias reload='source ~/.zshrc'
else
    alias reload='unset _BASHRC_LOADED; . ~/.bashrc'
fi
case ${OSTYPE:-} in
    msys*|cygwin*|MINGW*) ;;
    *)
        if [ -n "${AGENT_SHELL:-}" ]; then
            # Here `restart`/`poweroff` mean `sudo shutdown`. An agent typing
            # `restart` meaning "restart the service" must not halt the machine.
            # Defined as functions, not left as aliases — an alias would win at
            # parse time and a function alone could not shadow it.
            poweroff() { printf '%s\n' "refusing: 'poweroff' halts this machine, not a service" >&2; return 1; }
            restart()  { printf '%s\n' "refusing: 'restart' reboots this machine, not a service" >&2; return 1; }
        else
            alias poweroff='sudo shutdown -h now'
            alias restart='sudo shutdown -r now'
        fi
        ;;
esac
alias get-ip='curl -s ipecho.net/plain; echo'

# Clipboard (cross-platform pbcopy/pbpaste). Here, not in a tool file: the zle clipboard widgets in .personal.zsh need it before they are defined
if ! command -v pbcopy >/dev/null 2>&1; then
    if [ -e /dev/clipboard ]; then                  # MSYS2, Git Bash, Cygwin
        alias pbcopy='cat > /dev/clipboard'
        alias pbpaste='cat /dev/clipboard'
    elif [ -n "${WSL_DISTRO_NAME:-}" ] && command -v clip.exe >/dev/null 2>&1; then
        alias pbcopy='clip.exe'
        alias pbpaste="powershell.exe -NoProfile -Command Get-Clipboard | tr -d '\r'"
    elif command -v termux-clipboard-set >/dev/null 2>&1; then   # Termux, which waits forever without the Termux:API app
        _termux_clipboard() {
            local rc
            timeout 3 "$2"
            rc=$?
            [ "$rc" -ne 124 ] || { echo "$1 needs the Termux:API app" >&2; return 1; }
            return "$rc"
        }
        pbcopy() { _termux_clipboard pbcopy termux-clipboard-set; }
        pbpaste() { _termux_clipboard pbpaste termux-clipboard-get; }
    elif command -v wl-copy >/dev/null 2>&1; then
        alias pbcopy='wl-copy'
        alias pbpaste='wl-paste'
    elif command -v xclip >/dev/null 2>&1; then
        alias pbcopy='xclip -selection clipboard'
        alias pbpaste='xclip -selection clipboard -o'
    elif command -v xsel >/dev/null 2>&1; then
        alias pbcopy='xsel --clipboard --input'
        alias pbpaste='xsel --clipboard --output'
    fi
fi

# Utilities
alias uid="uuidgen | tr '[:upper:]' '[:lower:]'"
alias cat-line="awk '{ printf \"%s\\\\n\", \$0 }'"

lower() { if [ $# -gt 0 ]; then printf '%s\n' "$1"; else cat; fi | tr '[:upper:]' '[:lower:]'; }
upper() { if [ $# -gt 0 ]; then printf '%s\n' "$1"; else cat; fi | tr '[:lower:]' '[:upper:]'; }

guid_to_base64() {
    local guid_bytes encoded
    guid_bytes=$(printf '%s' "$1" | xxd -p -c 18 | tr -d '\n ')
    encoded=$(printf '%s' "$guid_bytes" | base64)
    printf '%s\n' "${encoded%?}"
}

base64_to_guid() {
    local guid_bytes
    guid_bytes=$(printf '%s' "${1}==" | base64 -d)
    printf '%s' "$guid_bytes" | xxd -r -p | sed 's/\(..\)/\1-/g; s/-$//'
}

# For the modern CLI replacements in the tool files (eza, bat, rg and the rest): only if installed, and never
# in agent shells. They shadow POSIX tools with incompatible flags, so an agent running `sed -i`, `du -sh`,
# `df -h` or `ls -t` would get a hard error instead of output.
alias-if-exists() {
    [ -n "${AGENT_SHELL:-}" ] && return 0
    command -v "$1" >/dev/null 2>&1 && alias "$2"
}
