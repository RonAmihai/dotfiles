# Environment for interactive zsh and bash, and for the zsh launchers in ~/.local/bin. POSIX syntax only, so bash 3.2 (macOS) can read it too.

# Ensure a sane file descriptor limit (macOS sometimes inherits a low 256)
ulimit -n 10240 2>/dev/null

# Locale (minimal Linux and WSL images ship C.UTF-8 but not en_US.UTF-8)
_locale=en_US.UTF-8
case ${OSTYPE:-} in
    linux*) locale -a 2>/dev/null | command grep -qiE '^en_US\.utf-?8$' || _locale=C.UTF-8 ;;
esac
export LC_CTYPE="$_locale"
export LC_ALL="$_locale"
unset _locale

# Where chezmoi rendered the dotfiles: the home folder, or the profile of a `work` session
_dotfiles_home=${DOTFILES_HOME:-$HOME}

# User scripts
PATH="$_dotfiles_home/.local/bin:$PATH"

# Each file in ~/.config/shell/tools becomes one function, and `_dotfiles_tools <phase>` calls them in name order.
# A cache keeps the functions, so a shell start opens one file instead of every tool file once per phase.
_tools_generate() {
    awk -v shell="${ZSH_VERSION:+zsh}" '
    BEGIN { ext = shell == "zsh" ? "\\.z?sh$" : "\\.sh$" }
    FNR == 1 {
        if (open) print "}"
        name = FILENAME
        sub(/.*\//, "", name)
        open = name ~ ext
        skip = !open
        if (skip) next
        sub(/\.z?sh$/, "", name)
        gsub(/[^A-Za-z0-9_]/, "_", name)
        print "_dotfiles_tool_" name "() { :"
        calls = calls "\n    _dotfiles_tool_" name
    }
    skip { next }
    shell != "zsh" && $0 == "[ -n \"${ZSH_VERSION:-}\" ] || return 0" { print "return 0"; skip = 1; next }
    { print }
    END {
        if (open) print "}"
        print "_dotfiles_tools() {\n    DOTFILES_PHASE=$1" calls "\n}"
    }' "$@"
}
# Parses the code without running it, so a tool file with a syntax error stays out and breaks only itself
_tools_parses() {
    eval "_dotfiles_parse_check() { :
$1
}" 2>/dev/null
}
_tools_build() {
    _tools_code=$(_tools_generate "$_dotfiles_home"/.config/shell/tools/*)
    _tools_parses "$_tools_code" && return
    set --
    _tools_warnings=
    for _tool in "$_dotfiles_home"/.config/shell/tools/*; do
        if _tools_parses "$(_tools_generate "$_tool")"; then
            set -- "$@" "$_tool"
        else
            _tools_warnings="${_tools_warnings}echo 'dotfiles: ${_tool##*/} has a syntax error, so this shell skips it' >&2
"
        fi
    done
    [ $# -gt 0 ] || set -- /dev/null
    _tools_code=$_tools_warnings$(_tools_generate "$@")
}
_tools_cache=$_dotfiles_home/.cache/shell/tools.${ZSH_VERSION:+zsh}${BASH_VERSION:+bash${BASH_VERSION%%.*}}
_tools_stale=
if [ ! -s "$_tools_cache" ] || [ "$_dotfiles_home/.config/shell/tools" -nt "$_tools_cache" ]; then
    _tools_stale=1
else
    for _tool in "$_dotfiles_home"/.config/shell/tools/*; do
        [ "$_tool" -nt "$_tools_cache" ] && { _tools_stale=1; break; }
    done
fi
if [ -n "$_tools_stale" ]; then
    _tools_build
    mkdir -p "${_tools_cache%/*}" 2>/dev/null
    if { printf '%s\n' "$_tools_code" > "$_tools_cache.$$"; } 2>/dev/null && mv -f "$_tools_cache.$$" "$_tools_cache" 2>/dev/null; then
        [ -n "${ZSH_VERSION:-}" ] && zcompile "$_tools_cache" 2>/dev/null
    else
        rm -f "$_tools_cache.$$" 2>/dev/null
        _tools_cache=
    fi
fi
# A read-only home, such as in an agent sandbox, cannot keep the cache
if [ -n "$_tools_cache" ]; then
    . "$_tools_cache"
else
    eval "$_tools_code"
fi
unset _tool _tools_cache _tools_stale _tools_code _tools_warnings _dotfiles_home
unset -f _tools_generate _tools_parses _tools_build _dotfiles_parse_check 2>/dev/null

# Each tool's PATH entries
_dotfiles_tools path

# Keep the first copy of each PATH entry: a prepended entry moves to the front, an appended one stays where it was.
# A relative entry would search the current folder, so a repo could plant commands: macOS's /etc/paths.d adds
# a literal ~/.dotnet/tools, which the shell never expands. ~/ becomes $HOME/, and any other relative entry goes.
_path_rest="$PATH:" PATH=
while [ -n "$_path_rest" ]; do
    _path_dir=${_path_rest%%:*}
    _path_rest=${_path_rest#*:}
    case $_path_dir in
        "~/"*) _path_dir="$HOME/${_path_dir#"~/"}" ;;
        /*) ;;
        *) continue ;;
    esac
    case ":$PATH:" in
        *":$_path_dir:"*) ;;
        *) [ -n "$_path_dir" ] && PATH=${PATH:+$PATH:}$_path_dir ;;
    esac
done
unset _path_rest _path_dir
export PATH

# Each tool's other exports, which can look up commands now that PATH is complete
_dotfiles_tools env
unset DOTFILES_PHASE

# Am I being sourced by an AI coding agent rather than a human at a terminal?
#
# Gates the interactive-only machinery: zsh plugins, the prompt, zoxide's `cd`,
# the modern CLI aliases, and the restart/poweroff aliases.
# Agent CLIs run non-interactive commands that assume POSIX tools and a plain `cd`.
#
# AI_AGENT / AGENT are the emerging cross-tool standard (agents.md#136 has not
# settled which name wins, so check both). AI_AGENT is verified present in
# Claude Code. The rest are vendor-specific fallbacks for tools that have not
# adopted the standard yet; sourced from vercel/detect-agent's agents.json.
AGENT_SHELL=
if [ -n "${AI_AGENT:-}${AGENT:-}${CLAUDECODE:-}${CLAUDE_CODE:-}${CURSOR_AGENT:-}${GEMINI_CLI:-}" ] \
|| [ -n "${CODEX_THREAD_ID:-}${CODEX_SANDBOX:-}${CODEX_CI:-}${ANTIGRAVITY_AGENT:-}${ANTIGRAVITY_CLI_ALIAS:-}" ] \
|| [ -n "${OPENCODE:-}${OPENCODE_CLIENT:-}${CLINE_ACTIVE:-}${GOOSE_PROVIDER:-}${AUGMENT_AGENT:-}${OPENCLAW_SHELL:-}" ] \
|| [ -n "${JUNIE_DATA:-}${JUNIE_SHIM_PATH:-}${COPILOT_MODEL:-}${COPILOT_ALLOW_ALL:-}" ] \
|| [ "${CURSOR_EXTENSION_HOST_ROLE:-}" = agent-exec ]; then
    AGENT_SHELL=1
fi
