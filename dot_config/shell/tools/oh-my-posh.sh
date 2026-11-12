case ${DOTFILES_PHASE:-} in
setup)
    # bash: oh-my-posh's init runs oh-my-posh twice per shell, so cache its init script with the secondary prompt filled in.
    # oh-my-posh needs bash 4.2 or later; macOS ships bash 3.2, which keeps its default prompt.
    if [ -n "${BASH_VERSION:-}" ] && [ -z "${AGENT_SHELL:-}" ] && _bashrc_4_2; then
        _omp_bash_init() {
            local theme=~/.config/oh-my-posh/cli-theme.omp.json bin line src
            # The v number is the cache format: raise it when this function changes what it writes
            local cache="${DOTFILES_HOME:-$HOME}/.cache/bash/oh-my-posh-v2-${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}.bash"
            bin=$(command -v oh-my-posh) && [ -r "$theme" ] || return 0
            if [ ! -s "$cache" ] || [ "$bin" -nt "$cache" ] || [ "$theme" -nt "$cache" ]; then
                line=$(oh-my-posh init bash --config "$theme") || return 0
                src=${line##*source \$\'}
                src=${src%\'}
                # A future oh-my-posh may print its init line in another form: run it uncached rather than lose the prompt
                if [ ! -r "$src" ]; then
                    eval "$line"
                    return
                fi
                mkdir -p "${cache%/*}"
                line=${line%%;source*}
                {
                    # A new session ID for each shell, because oh-my-posh keeps a cache per session
                    printf '%s\n' 'printf -v POSH_SESSION_ID "%08x-%04x-4%03x-%04x-%04x%04x%04x" $$ $RANDOM $((RANDOM % 4096)) $((RANDOM % 16384 + 32768)) $RANDOM $RANDOM $RANDOM; export POSH_SESSION_ID'
                    printf '%s\n' "${line#export POSH_SESSION_ID=\"*\"; }"
                    OMP_SECONDARY="$(printf '_omp_secondary_prompt=%q' "$(oh-my-posh print secondary --shell=bash --shell-version="$BASH_VERSION" --config "$theme")")" \
                        awk '/^_omp_secondary_prompt=\$\($/ { print ENVIRON["OMP_SECONDARY"]; skip = 1; next }
                             skip && /^\)$/ { skip = 0; next }
                             !skip' "$src"
                } > "$cache"
            fi
            . "$cache"
        }
        _omp_bash_init
    fi ;;
esac
[ -n "${ZSH_VERSION:-}" ] || return 0

case $DOTFILES_PHASE in
setup)
    # zsh: the prompt, with its init script cached per terminal and the secondary prompt filled in
    [[ -z "$AGENT_SHELL" ]] && () {
        (( $+commands[oh-my-posh] )) || return
        local _OMP_CACHE_DIR="${DOTFILES_HOME:-$HOME}/.cache/oh-my-posh"
        local _term_id="${TERM_PROGRAM:-unknown}"
        local _OMP_INIT_CACHE="$_OMP_CACHE_DIR/init-patched-${_term_id}.zsh"
        local _OMP_SECONDARY_CACHE="$_OMP_CACHE_DIR/secondary-prompt-${_term_id}.cache"
        # An oh-my-posh upgrade changes its init script, so the cache's first line records the binary that built it.
        # The leading number is the cache format: raise it when this function changes what it writes.
        local -a _omp_mtime
        zmodload -F zsh/stat b:zstat 2>/dev/null && zstat -A _omp_mtime +mtime -- ${commands[oh-my-posh]:A} 2>/dev/null
        local _omp_stamp="# 3 ${commands[oh-my-posh]:A} ${_omp_mtime[1]}" _omp_cached_stamp=
        [[ -r "$_OMP_INIT_CACHE" ]] && read -r _omp_cached_stamp < "$_OMP_INIT_CACHE"

        if [[ $_omp_cached_stamp != $_omp_stamp ]] || [[ ~/.config/oh-my-posh/cli-theme.omp.json -nt "$_OMP_INIT_CACHE" ]]; then
            mkdir -p "$_OMP_CACHE_DIR"
            # Generate OMP init which outputs: export POSH_SESSION_ID="...";source $'/path/to/init.zsh'
            local _omp_init_line=$(oh-my-posh init zsh --config ~/.config/oh-my-posh/cli-theme.omp.json 2>/dev/null)
            # Extract the sourced init file path
            local _omp_init_source=$(echo "$_omp_init_line" | grep -oE "source \\\$'[^']+'" | sed "s/source \\\$'//;s/'$//")
            # A future oh-my-posh may print its init line in another form: run it uncached rather than lose the prompt
            if [[ ! -r "$_omp_init_source" ]]; then
                eval "$_omp_init_line"
                return
            fi
            # Cache secondary prompt, and patch the init file to read the cache instead of running oh-my-posh
            local _omp_patch
            if grep -q 'print secondary --shell=zsh --eval' "$_omp_init_source"; then
                # oh-my-posh 31 and later eval the secondary prompt settings
                command oh-my-posh print secondary --shell=zsh --eval --config ~/.config/oh-my-posh/cli-theme.omp.json > "$_OMP_SECONDARY_CACHE" 2>/dev/null
                _omp_patch="s|^eval \"\\\$(\\\$_omp_executable print secondary --shell=zsh --eval)\"\$|source '$_OMP_SECONDARY_CACHE'|"
            else
                command oh-my-posh print secondary --shell=zsh --config ~/.config/oh-my-posh/cli-theme.omp.json > "$_OMP_SECONDARY_CACHE" 2>/dev/null
                # Read secondary prompt and escape for sed replacement
                local _secondary_escaped=$(cat "$_OMP_SECONDARY_CACHE" | sed 's/[&/\]/\\&/g')
                _omp_patch="s/\\\$(\\\$_omp_executable print secondary --shell=zsh)/'$_secondary_escaped'/"
            fi
            # Create patched init: a new session ID for each shell (oh-my-posh keeps a cache per session), the config export, the patched init file
            {
                print -r -- "$_omp_stamp"
                print -r -- 'printf -v POSH_SESSION_ID "%08x-%04x-4%03x-%04x-%04x%04x%04x" $$ $RANDOM $((RANDOM % 4096)) $((RANDOM % 16384 + 32768)) $RANDOM $RANDOM $RANDOM; export POSH_SESSION_ID'
                echo "$_omp_init_line" | sed 's/;source.*//; s/export POSH_SESSION_ID="[^"]*"; *//'
                sed "$_omp_patch" "$_omp_init_source"
            } > "$_OMP_INIT_CACHE"
            zcompile "$_OMP_INIT_CACHE" 2>/dev/null
        fi
        [[ -f "$_OMP_INIT_CACHE" ]] && source "$_OMP_INIT_CACHE"
    } ;;
esac
