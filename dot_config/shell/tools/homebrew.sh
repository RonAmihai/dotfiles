case ${DOTFILES_PHASE:-} in
path)
    # Homebrew on macOS (Apple Silicon, Intel) and Linux (system-wide, per-user): what `brew shellenv` sets, without running brew
    export HOMEBREW_NO_ENV_HINTS=true
    for _brew_prefix in /opt/homebrew /home/linuxbrew/.linuxbrew "$HOME/.linuxbrew" /usr/local; do
        [ -x "$_brew_prefix/bin/brew" ] && break
        _brew_prefix=
    done
    if [ -n "$_brew_prefix" ]; then
        export HOMEBREW_PREFIX="$_brew_prefix"
        export HOMEBREW_CELLAR="$HOMEBREW_PREFIX/Cellar"
        if [ -d "$HOMEBREW_PREFIX/Homebrew" ]; then
            export HOMEBREW_REPOSITORY="$HOMEBREW_PREFIX/Homebrew"
        else
            export HOMEBREW_REPOSITORY="$HOMEBREW_PREFIX"
        fi
        PATH="$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin:$PATH"
        export MANPATH="$HOMEBREW_PREFIX/share/man:${MANPATH:-}"
        export INFOPATH="$HOMEBREW_PREFIX/share/info:${INFOPATH:-}"
    fi
    unset _brew_prefix
    return 0 ;;
aliases)
    # Intel Homebrew under Rosetta; Apple's git fails there on macOS 27, which has no x86_64 libxcrun
    case ${OSTYPE:-}:${CPUTYPE:-${HOSTTYPE:-}} in
        darwin*:arm64|darwin*:aarch64) alias xbrew='HOMEBREW_GIT_PATH=/opt/homebrew/bin/git arch --x86_64 /usr/local/bin/brew' ;;
    esac
    return 0 ;;
esac
[ -n "${ZSH_VERSION:-}" ] || return 0

case $DOTFILES_PHASE in
setup)
    if [[ -n $HOMEBREW_PREFIX ]] && (( ! ${fpath[(Ie)$HOMEBREW_PREFIX/share/zsh/site-functions]} )); then
        fpath=("$HOMEBREW_PREFIX/share/zsh/site-functions" $fpath)
    fi ;;
update)
    _update_add 20 brew _update_homebrew
    # Homebrew on macOS and Linux, plus the Intel Homebrew in /usr/local that runs under Rosetta on Apple Silicon
    _update_homebrew() {
        local native_brew=${commands[brew]} prefix
        # Also finds Homebrew when the calling shell did not put it on PATH, for example bash or cron
        for prefix in /opt/homebrew /home/linuxbrew/.linuxbrew ~/.linuxbrew /usr/local; do
            [[ -z $native_brew && -x $prefix/bin/brew ]] && native_brew=$prefix/bin/brew
        done
        local -a brews=()
        [[ -n $native_brew ]] && brews+=("$native_brew|Homebrew")
        if [[ $OSTYPE == darwin* && $CPUTYPE == arm64 && -x /usr/local/bin/brew && ${native_brew:A} != ${${:-/usr/local/bin/brew}:A} ]]; then
            brews+=("HOMEBREW_GIT_PATH=/opt/homebrew/bin/git arch --x86_64 /usr/local/bin/brew|Homebrew (x64)")
        fi
        (( ${#brews} )) || return 0

        if [[ $mode == clean ]]; then
            # A tool run with sudo can write root-owned files into its keg, and brew cleanup cannot delete that keg later
            _brew_own_old_kegs() {
                (( EUID )) || return 0
                local brew_cmd=$1
                local cellar=$(eval "$brew_cmd --cellar" 2>/dev/null) prefix=$(eval "$brew_cmd --prefix" 2>/dev/null)
                [[ -d $cellar && -d $prefix ]] || return 0
                local -aU kegs=()
                local file keg
                for file in ${(f)"$(find "$cellar" -mindepth 2 ! -user "$USERNAME" 2>/dev/null)"}; do
                    keg=${(M)file##$cellar/[^/]##/[^/]##}
                    [[ ${keg:A} == ${${:-$prefix/opt/${keg:h:t}}:A} ]] || kegs+=($keg)
                done
                (( ${#kegs} )) || return 0
                print -rl -- "  Another user owns files in: "${^kegs}
                _update_sudo chown -R "$USERNAME" $kegs
            }

            local entry
            for entry in $brews; do
                _update_step "${entry#*|} Cleanup" "_brew_own_old_kegs ${(q)${entry%%|*}}; ${entry%%|*} cleanup && ${entry%%|*} autoremove"
            done
            return 0
        fi

        # Sync receipts for casks updated outside brew (macOS only)
        _sync_brew_caskroom_receipts() {
            local brew_cmd=$1
            local prefix=$(eval "$brew_cmd --prefix" 2>/dev/null)
            local caskroom="$prefix/Caskroom"
            [[ -d "$caskroom" ]] || return 0
            local stale=("${(@f)$(eval "$brew_cmd outdated --cask --greedy --quiet" 2>/dev/null)}")
            [[ -n "${stale[1]}" ]] || return 0
            local json=$(eval "$brew_cmd info --cask --json=v2 ${stale[*]}" 2>/dev/null)
            [[ -n "$json" ]] || return 0
            local cask app_name actual meta
            while IFS=$'\t' read -r cask app_name; do
                [[ -f "/Applications/$app_name/Contents/Info.plist" ]] || continue
                actual=$(defaults read "/Applications/$app_name/Contents/Info" CFBundleShortVersionString 2>/dev/null)
                [[ -n "$actual" && ! -d "$caskroom/$cask/$actual" ]] || continue
                # Rename version directory
                for old_dir in "$caskroom/$cask"/*(N/); do
                    [[ "${old_dir:t}" == .metadata ]] && continue
                    mv "$old_dir" "$caskroom/$cask/$actual" 2>/dev/null && break
                done
                # Rename .metadata version directory
                meta="$caskroom/$cask/.metadata"
                if [[ -d "$meta" && ! -d "$meta/$actual" ]]; then
                    for old_dir in "$meta"/[0-9]*(N/); do
                        mv "$old_dir" "$meta/$actual" 2>/dev/null && break
                    done
                fi
                # Update version in install receipt
                if [[ -f "$meta/INSTALL_RECEIPT.json" ]]; then
                    jq --arg v "$actual" '.source.version = $v' "$meta/INSTALL_RECEIPT.json" > "$meta/INSTALL_RECEIPT.json.tmp" \
                        && mv "$meta/INSTALL_RECEIPT.json.tmp" "$meta/INSTALL_RECEIPT.json"
                fi
                printf '\033[0;90m  Synced %s receipt → %s\033[0m\n' "$cask" "$actual"
            done < <(echo "$json" | jq -r '
                .casks[] | . as $c |
                [.artifacts[] | .app? // empty | .[]] |
                if length > 0 then "\($c.token)\t\(.[0])" else empty end
            ' 2>/dev/null)
        }

        _update_brew() {
            local brew_cmd=$1 label=$2
            _update_header "$label"
            if (( ! dry_run )); then
                [[ $OSTYPE == darwin* ]] && _sync_brew_caskroom_receipts "$brew_cmd"
                local formulae=("${(@f)$(eval "$brew_cmd outdated --formula --quiet" 2>/dev/null)}")
                local casks=()
                [[ $OSTYPE == darwin* ]] && casks=("${(@f)$(eval "$brew_cmd outdated --cask --greedy --quiet" 2>/dev/null)}")
                [[ -n "${formulae[1]}" ]] && printf '  Formulae (%d): %s\n' "${#formulae[@]}" "${(j:, :)formulae}"
                [[ -n "${casks[1]}" ]] && printf '  Casks (%d): %s\n' "${#casks[@]}" "${(j:, :)casks}"
                [[ -z "${formulae[1]}" && -z "${casks[1]}" ]] && printf '\033[0;90m  All packages up to date\033[0m\n'
            fi
            # Homebrew clears the sudo ticket in each new brew process, and brew cu starts one per cask
            local upgrade_cmd="HOMEBREW_NO_ASK=1 HOMEBREW_SUDO_CHECKED=1 $brew_cmd upgrade --formula"
            # brew cu comes from the buo/cask-upgrade tap
            if [[ $OSTYPE == darwin* && -d $(eval "$brew_cmd --repository" 2>/dev/null)/Library/Taps/buo/homebrew-cask-upgrade ]]; then
                upgrade_cmd+=" && HOMEBREW_SUDO_CHECKED=1 $brew_cmd cu --include-mas --all --yes --force"
            fi
            _update_run "$upgrade_cmd"
        }

        # Read-only on purpose: brew bundle cleanup offers to uninstall when it runs in a terminal
        _brew_drift() {
            local brew_cmd=$1 brewfiles_dir=${XDG_CONFIG_HOME:-$HOME/.config}/homebrew
            local -a brewfiles=($brewfiles_dir/Brewfile(N) $brewfiles_dir/*.Brewfile(N))
            (( ${#brewfiles} )) || return 0
            local -a listed=("${(@f)$(cat $brewfiles | eval "$brew_cmd bundle list --formula --cask --tap --file=-" 2>/dev/null)}")
            local -a wanted=("${(@f)$(eval "$brew_cmd leaves --installed-on-request; $brew_cmd tap" 2>/dev/null)}")
            local -a present=("${(@f)$(eval "$brew_cmd list --formula --full-name; $brew_cmd tap" 2>/dev/null)}")
            if [[ $OSTYPE == darwin* ]]; then
                local -a casks=("${(@f)$(eval "$brew_cmd list --cask" 2>/dev/null)}")
                wanted+=($casks)
                present+=($casks)
            fi
            local -a extra=(${${wanted:|listed}:#}) missing=(${${listed:|present}:#})
            if (( ${#extra} )); then
                printf '  In no Brewfile (%d): %s\n' ${#extra} "${(j:, :)extra}"
                printf '\033[0;90m  Add them with chezmoi edit %s/Brewfile, or remove them with brew uninstall\033[0m\n' "$brewfiles_dir"
            fi
            if (( ${#missing} )); then
                printf '  In a Brewfile but not installed (%d): %s\n' ${#missing} "${(j:, :)missing}"
                printf '\033[0;90m  Install them with brew bundle install --file <Brewfile>\033[0m\n'
            fi
            return 0
        }

        local entry
        for entry in $brews; do
            _update_brew "${entry%%|*}" "${entry#*|}"
            [[ ${entry%%|*} == $native_brew ]] && (( ! dry_run )) && _brew_drift "$native_brew"
        done
    } ;;
esac
