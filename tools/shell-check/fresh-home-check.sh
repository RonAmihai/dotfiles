#!/usr/bin/env bash
# Usage: bash tools/shell-check/fresh-home-check.sh [--home DIR]   — fails if zsh or bash prints an error or differs from the other shell
# Works with bash 3.2. Tests every shell it finds: zsh, the bash on PATH, and /bin/bash when that is a different version.
# Without --home it copies the shell files into an empty HOME; with --home it tests a HOME that `chezmoi apply` rendered.

repo=$(cd "$(dirname "$0")/../.." && pwd)
failed=0
export LC_ALL=C

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
if [ "${1:-}" = --home ] && [ -d "${2:-}" ]; then
    home=$(cd "$2" && pwd)
else
    home=$scratch/home
    mkdir -p "$home/.config"
    cp "$repo/dot_zshenv" "$home/.zshenv"
    cp "$repo/dot_zshrc" "$home/.zshrc"
    cp "$repo/dot_personal.zsh" "$home/.personal.zsh"
    cp "$repo/dot_bashrc" "$home/.bashrc"
    cp "$repo/dot_bash_profile" "$home/.bash_profile"
    cp "$repo/dot_inputrc" "$home/.inputrc"
    mkdir -p "$home/.ssh"
    cp "$repo/private_dot_ssh/private_config" "$home/.ssh/config"
    for d in zsh shell oh-my-posh; do
        cp -R "$repo/dot_config/$d" "$home/.config/$d"
    done
fi
empty_home=$scratch/empty-home
mkdir -p "$empty_home"
# Any zsh startup file stops zsh from asking its new-user setup questions
touch "$empty_home/.zshrc"

zsh_bin=$(command -v zsh)
bash_bins=$(command -v bash)
if [ -x /bin/bash ] && [ "$(/bin/bash -c 'echo $BASH_VERSION')" != "$(bash -c 'echo $BASH_VERSION')" ]; then
    bash_bins="$bash_bins /bin/bash"
fi

syntax() {
    local checker=$1 file
    shift
    for file in "$@"; do
        [ -f "$file" ] || continue
        if ! $checker -n "$file"; then
            echo "FAIL: $checker syntax error in ${file#$repo/}"
            failed=1
        fi
    done
}
shared=$(ls "$repo"/dot_config/shell/*.sh)
tool_files=$(ls "$repo"/dot_config/shell/tools/*.sh)
for b in $bash_bins; do
    syntax "$b" $shared "$repo/dot_bashrc" "$repo/dot_bash_profile" "$repo/tools/shell-check/fresh-home-check.sh"
    # bash stops reading a tool file at its zsh-only line, so it only has to parse the part before it
    for f in $tool_files; do
        if ! sed '/^\[ -n "\${ZSH_VERSION:-}" \] || return 0$/q' "$f" | "$b" -n; then
            echo "FAIL: $b syntax error in ${f#$repo/}"
            failed=1
        fi
    done
done
if [ -n "$zsh_bin" ]; then
    zsh_files=$(ls "$repo"/dot_config/shell/tools/*.zsh "$repo"/dot_config/zsh/*/*.zsh "$repo"/tools/*/*.zsh 2>/dev/null)
    syntax "$zsh_bin" $shared $tool_files "$repo/dot_zshenv" "$repo/dot_zshrc" "$repo/dot_personal.zsh" \
        $zsh_files "$repo/dot_local/bin/executable_update-all" "$repo/dot_local/bin/executable_update-chrome"
fi

user=${USER:-${USERNAME:-ci}}
login_env="USER=$user LOGNAME=$user TERM=xterm-256color PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

bash_version() {
    "$1" -c 'echo ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}'
}

# Without a terminal, bash -i reports missing job control and bash 3.2's readline emits its meta-key code; a real terminal shows neither
check() {
    local label=$1 errors
    shift
    errors=$(cd "$home" && env -i HOME="$home" $login_env "$@" 2>&1 >/dev/null \
        | command sed $'s/\e\\[?1034h//g' \
        | command grep -v -e '^$' -e 'no job control in this shell' -e 'cannot set terminal process group' -e 'Inappropriate ioctl')
    if [ -n "$errors" ]; then
        echo "FAIL: the $label shell printed errors:"
        echo "$errors"
        failed=1
    else
        echo "ok: the $label shell starts with no errors"
    fi
}

# Writes to files, because startup files in /etc can print to the terminal (Fedora's zlogout runs clear)
probe='for v in AGENT_SHELL LC_ALL LC_CTYPE EDITOR VISUAL HOMEBREW_PREFIX HOMEBREW_REPOSITORY FZF_DEFAULT_COMMAND FZF_ALT_C_COMMAND PATH; do eval "echo \"$v=\${$v:-}\""; done > "$PROBE_OUT/values"; alias > "$PROBE_OUT/aliases"; { command -v oh-my-posh || echo; echo "${POSH_CONFIG:-}"; } > "$PROBE_OUT/prompt"'

dump() {
    local out=$1 dump_home=$2
    shift 2
    mkdir -p "$out"
    (cd "$dump_home" && env -i HOME="$dump_home" PROBE_OUT="$out" $login_env "$@" -il -c "$probe" >/dev/null 2>&1)
    if [ ! -s "$out/values" ]; then
        echo "FAIL: the shell for ${out##*/} wrote no values"
        failed=1
    fi
}

path_of() {
    sed -n 's/^PATH=//p' "$1/values"
}

path_without() {
    local IFS=: dir kept=
    for dir in $1; do
        case ":$2:" in
            *":$dir:"*) ;;
            *) kept=${kept:+$kept:}$dir ;;
        esac
    done
    echo "$kept"
}

# Distros give zsh and bash different PATHs and aliases in /etc, so compare only what the dotfiles add to a run without them
dotfiles_part() {
    local dir=$1 baseline=$2 system_path=$3
    grep -v '^PATH=' "$dir/values"
    echo "PATH=$(path_without "$(path_of "$dir")" "$system_path")"
    comm -13 <(sort "$baseline/aliases") <(sort "$dir/aliases") | sed -e 's/^alias //' -e 's/=.*//' | sort
}

# A human zsh, or bash 4.2 or later, loads the theme when oh-my-posh is installed; an agent shell never loads it
prompt_check() {
    local label=$1 dir=$2 expected=$3 omp config
    [ -r "$dir/prompt" ] || return 0
    { read -r omp; read -r config; } < "$dir/prompt"
    [ -n "$omp" ] || return 0
    if [ "$expected" = theme ]; then
        case $config in
            *cli-theme.omp.json) echo "ok: the $label shell loads the oh-my-posh theme" ;;
            *) echo "FAIL: the $label shell has oh-my-posh but did not load the theme"; failed=1 ;;
        esac
    elif [ -n "$config" ]; then
        echo "FAIL: the $label shell loaded oh-my-posh, which it must not do"
        failed=1
    else
        echo "ok: the $label shell does not load oh-my-posh"
    fi
}

if [ -n "$zsh_bin" ]; then
    dump "$scratch/zsh-baseline" "$empty_home" "$zsh_bin"
    for b in $bash_bins; do
        dump "$scratch/bash-$(bash_version "$b")-baseline" "$empty_home" "$b"
    done
fi

for mode in human agent; do
    marker=
    [ $mode = agent ] && marker=AI_AGENT=fresh-home-check
    if [ -n "$zsh_bin" ]; then
        check "zsh $mode" $marker "$zsh_bin" -il -c true
        if [ $mode = human ]; then
            check "zsh human (late completion setup)" "$zsh_bin" -il -c \
                'autoload -Uz compinit && compinit -u -d "$HOME/.zcompdump-check" && _dotfiles_after_compinit'
        fi
        dump "$scratch/zsh-$mode" "$home" $marker "$zsh_bin"
        prompt_check "zsh $mode" "$scratch/zsh-$mode" "$([ $mode = human ] && echo theme)"
    fi
    for b in $bash_bins; do
        version=$(bash_version "$b")
        check "bash $version $mode" $marker "$b" -il -c true
        dump "$scratch/bash-$version-$mode" "$home" $marker "$b"
        case $mode-$version in
            human-3.*|human-4.[01]) prompt_check "bash $version $mode" "$scratch/bash-$version-$mode" none ;;
            *) prompt_check "bash $version $mode" "$scratch/bash-$version-$mode" "$([ $mode = human ] && echo theme)" ;;
        esac
        [ -n "$zsh_bin" ] || continue
        system_path="$(path_of "$scratch/zsh-baseline"):$(path_of "$scratch/bash-$version-baseline")"
        zsh_part=$(dotfiles_part "$scratch/zsh-$mode" "$scratch/zsh-baseline" "$system_path")
        bash_part=$(dotfiles_part "$scratch/bash-$version-$mode" "$scratch/bash-$version-baseline" "$system_path")
        if [ "$zsh_part" = "$bash_part" ]; then
            echo "ok: zsh and bash $version ($mode) agree on values, PATH and aliases"
        else
            echo "FAIL: zsh and bash $version ($mode) differ:"
            diff <(echo "$zsh_part") <(echo "$bash_part") | sed 's/^/  /'
            failed=1
        fi
    done
done

# oh-my-posh falls back to its default theme without an error, so the theme must render differently from a missing one
theme="$home/.config/oh-my-posh/cli-theme.omp.json"
omp=$(head -n 1 "$scratch/bash-$(bash_version "${bash_bins%% *}")-human/prompt")
if [ -n "$omp" ] && [ -r "$theme" ]; then
    mine=$(cd "$home" && env -i HOME="$home" $login_env "$omp" print primary --shell bash --config "$theme" 2>&1)
    fallback=$(cd "$home" && env -i HOME="$home" $login_env "$omp" print primary --shell bash --config "$home/missing.omp.json" 2>&1)
    if [ -n "$mine" ] && [ "$mine" != "$fallback" ]; then
        echo "ok: oh-my-posh $("$omp" version 2>/dev/null) renders the theme"
    else
        echo "FAIL: oh-my-posh did not render the theme:"
        echo "$mine"
        failed=1
    fi
fi

if command -v ssh >/dev/null 2>&1 && [ -r "$home/.ssh/config" ]; then
    if errors=$(ssh -G -F "$home/.ssh/config" example.com 2>&1 </dev/null >/dev/null); then
        echo "ok: $(ssh -V 2>&1 | cut -d, -f1) reads ~/.ssh/config with no errors"
    else
        echo "FAIL: ssh cannot read ~/.ssh/config:"
        echo "$errors"
        failed=1
    fi
fi

[ -n "$zsh_bin" ] && check "zsh script" "$zsh_bin" -c true
for b in $bash_bins; do
    check "bash $(bash_version "$b") script" "$b" -c true
done

exit $failed
