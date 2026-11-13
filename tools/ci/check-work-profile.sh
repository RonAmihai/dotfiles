#!/usr/bin/env bash
# Usage: bash tools/ci/check-work-profile.sh HOME [check ...] — runs the work command on a copy of a HOME that chezmoi rendered without a work layer, with tools/work-layer-skeleton as the work layer; one ok: or FAIL: line per check
set -uo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
rendered=$(cd "$1" && pwd)
shift
termux=
[ -x /data/data/com.termux/files/usr/bin/pkg ] && termux=1
if [ $# -eq 0 ]; then
    set -- session_env work_identity forbidden_terms personal_kept work_tools no_leak stale_warning refuses_with_work_layer agents_no_leak
    [ -n "$termux" ] && set -- "$@" clean_keeps_live
fi
real_home=$HOME
skeleton=$repo/tools/work-layer-skeleton
chezmoi_bin=${CHEZMOI:-$(command -v chezmoi)}
zsh_bin=$(command -v zsh)
sh_path=$(command -v sh)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
failed=0

ok() { echo "ok: $1"; }
fail() { echo "FAIL: $1"; failed=1; }

# A scratch PREFIX and TMPDIR, so the checks never touch a real work profile
prefix=$scratch/prefix
tmp=$scratch/tmp
mkdir -p "$prefix/tmp" "$prefix/bin" "$tmp"
[ -n "$termux" ] && ln -s "$PREFIX/bin/sh" "$prefix/bin/sh"
if [ -n "$termux" ]; then
    profile=$prefix/tmp/work-profile
else
    profile=$tmp/work-profile-$(id -u)
fi
home=$scratch/home
cp -R "$rendered/." "$home"
mkdir -p "$home/.config/chezmoi" "$home/.config/gh"
printf 'sourceDir = "%s"\n[data]\n    name = "CI"\n    work_dotfiles_repo = ""\n' "$repo" > "$home/.config/chezmoi/chezmoi.toml"
printf 'github.com:\n    user: ci\n' > "$home/.config/gh/hosts.yml"
fakes=$scratch/fakes
mkdir -p "$fakes"
printf '#!%s\necho "agy home: $HOME"\n' "$sh_path" > "$fakes/agy"
chmod +x "$fakes/agy"
session_path=$fakes:$home/.local/bin:${chezmoi_bin%/*}:$PATH

# Runs a command the way a new terminal session would
fresh() {
    (cd "$home" && env -i HOME="$home" PREFIX="$prefix" TMPDIR="$tmp" TERM=dumb USER=ci PATH="$session_path" "$@" </dev/null)
}
work() {
    fresh bash "$repo/dot_local/bin/executable_work" --source "$skeleton" "$@" 2>"$scratch/work.err"
}

check_session_env() {
    local out bad='' v
    out=$(work -c 'env; echo "agy=$(command -v agy)"; agy')
    for v in CLAUDE_CONFIG_DIR CODEX_HOME GH_CONFIG_DIR GLAB_CONFIG_DIR XDG_CONFIG_HOME XDG_CACHE_HOME HISTFILE DOTFILES_HOME \
        DOTNET_CLI_HOME NUGET_PACKAGES npm_config_cache GOPATH; do
        printf '%s\n' "$out" | grep -q "^$v=$profile/home" || bad="$bad $v"
    done
    printf '%s\n' "$out" | grep -qx "GIT_CONFIG_GLOBAL=$profile/gitconfig" || bad="$bad GIT_CONFIG_GLOBAL"
    printf '%s\n' "$out" | grep -qx "agy=$profile/home/.local/bin/agy" || bad="$bad agy-path"
    printf '%s\n' "$out" | grep -qx "agy home: $profile/home" || bad="$bad agy-HOME"
    if [ -z "$bad" ]; then
        ok "session_env: the tool variables, the package caches, git and agy point into the profile"
    else
        fail "session_env: wrong:$bad ($(head -c 300 "$scratch/work.err"))"
    fi
}

check_work_identity() {
    local out
    out=$(work -c 'cd "$(mktemp -d)" && git init -q && git remote add origin https://github.com/example-org/x && git config user.email')
    if [ "$out" = you@example.com ]; then
        ok "work_identity: a repo with a work remote gets the work email"
    else
        fail "work_identity: user.email is '$out'"
    fi
}

check_forbidden_terms() {
    local out
    grep -q 'XDG_CONFIG_HOME:-$HOME/.config}"/chezmoi/forbidden-terms.d/' "$repo/.githooks/pre-push" ||
        { fail "forbidden_terms: the pre-push hook no longer reads the folder through XDG_CONFIG_HOME"; return; }
    out=$(work -c 'cat "${XDG_CONFIG_HOME:-$HOME/.config}"/chezmoi/forbidden-terms.d/work')
    if printf '%s\n' "$out" | grep -q 'pre-push hook reads this folder'; then
        ok "forbidden_terms: in a session, the pre-push hook finds the work layer's terms"
    else
        fail "forbidden_terms: the hook's folder has no work terms in a session"
    fi
}

check_personal_kept() {
    local out
    out=$(work -c 'grep -c "^Chezmoi manages the dotfiles" "$CLAUDE_CONFIG_DIR/CLAUDE.md"; cat "$GH_CONFIG_DIR/hosts.yml"')
    if printf '%s\n' "$out" | grep -qx 1 && printf '%s\n' "$out" | grep -q 'user: ci'; then
        ok "personal_kept: the profile has the personal agent rules and the GitHub login"
    else
        fail "personal_kept: missing the personal rules or the GitHub login: $out"
    fi
}

check_work_tools() {
    local out
    out=$(work -c 'zsh -i -c "typeset -f _dotfiles_tool_chezmoi_work >/dev/null && echo loaded" 2>/dev/null')
    if [ "$out" = loaded ]; then
        ok "work_tools: an interactive shell in a session loads the work layer's tool files"
    else
        fail "work_tools: the work tool file did not load: '$out'"
    fi
}

check_no_leak() {
    local leaks
    rm -rf "$home/.cache"
    touch "$scratch/before"
    sleep 1
    work -c 'zsh -i -c true; bash -i -c true; git config --global user.name' >/dev/null
    leaks=$(find "$home" \( -type f -o -type l \) -newer "$scratch/before" -print)
    if [ -n "$leaks" ]; then
        fail "no_leak: the session changed files in the home folder: $(printf '%s\n' "$leaks" | tr '\n' ' ')"
    elif [ -e "$profile" ]; then
        fail "no_leak: the profile is still on disk after the session"
    else
        ok "no_leak: a session changes no file in the home folder, and its profile is gone after it"
    fi
}

check_stale_warning() {
    local out
    mkdir -p "$profile"
    echo 2026-01-02 03:04 > "$profile/started"
    "$sh_path" -c 'echo $$' > "$profile/pid"
    out=$(fresh "$zsh_bin" -i -c true 2>&1)
    rm -rf "$profile"
    if printf '%s\n' "$out" | grep -q 'work profile from 2026-01-02 03:04 is still on disk: run work --end'; then
        ok "stale_warning: a new shell names a profile that a closed session left"
    else
        fail "stale_warning: no warning in: $out"
    fi
}

check_refuses_with_work_layer() {
    local out
    mkdir -p "$home/.config/git"
    : > "$home/.config/git/work.gitconfig"
    out=$(work -c true 2>&1; cat "$scratch/work.err")
    rm -f "$home/.config/git/work.gitconfig"
    if printf '%s\n' "$out" | grep -q 'has the work layer installed' && [ ! -e "$profile" ]; then
        ok "refuses_with_work_layer: a machine with the work layer installed keeps it, with no session"
    else
        fail "refuses_with_work_layer: work did not refuse: $out"
    fi
}

# Runs each installed agent once in a session, without a login, so a file that an agent writes outside its profile shows up
check_agents_no_leak() {
    local agents='' agent real leaks
    if [ -n "$termux" ] && [ ! -x /usr/bin/pkg ]; then
        echo "skip: agents_no_leak runs inside termux-chroot, because outside it termux-chroot gives the agents the real HOME"
        return
    fi
    mkdir -p "$home/.local/bin"
    if [ -n "$termux" ]; then
        if [ -x "$real_home/.local/share/claude/claude-native" ]; then
            mkdir -p "$home/.local/share/claude"
            ln -sf "$real_home/.local/share/claude/claude-native" "$home/.local/share/claude/claude-native"
            agents="$agents claude"
        fi
        if [ -d "$real_home/.codex/packages/standalone/current" ]; then
            mkdir -p "$home/.codex/packages/standalone"
            ln -sfn "$(cd "$real_home/.codex/packages/standalone/current" && pwd -P)" "$home/.codex/packages/standalone/current"
            agents="$agents codex"
        fi
        [ -x "$real_home/.local/bin/agy" ] && ln -sf "$real_home/.local/bin/agy" "$home/.local/bin/agy" && agents="$agents agy"
    else
        for agent in claude codex agy; do
            real=$(command -v "$agent") || continue
            ln -sf "$(realpath "$real")" "$home/.local/bin/$agent" && agents="$agents $agent"
        done
    fi
    if [ -z "$agents" ]; then
        echo "skip: agents_no_leak needs Claude Code, Codex or agy, and none is installed"
        return
    fi
    mv "$fakes/agy" "$fakes/agy.off"
    touch "$scratch/agents-before"
    sleep 1
    work -c "for agent in $agents; do
        case \$agent in
            claude) timeout 60 claude -p 'Reply with ok' ;;
            codex) timeout 30 codex exec --skip-git-repo-check 'Reply with ok' ;;
            agy) timeout 20 agy -p 'Reply with ok' ;;
        esac
    done" >/dev/null 2>&1
    mv "$fakes/agy.off" "$fakes/agy"
    leaks=$(find "$home" \( -type f -o -type l \) -newer "$scratch/agents-before" -print)
    if [ -n "$leaks" ]; then
        fail "agents_no_leak: in a session,$agents wrote to the home folder: $(printf '%s\n' "$leaks" | head -n 20 | tr '\n' ' ')"
    else
        ok "agents_no_leak:$agents wrote nothing to the home folder in a session"
    fi
}

check_clean_keeps_live() {
    mkdir -p "$profile" "$prefix/tmp/junk"
    echo $$ > "$profile/pid"
    fresh "$zsh_bin" "$home/.local/bin/update-all" --clean termux-caches >/dev/null 2>&1
    if [ -d "$profile" ] && [ ! -e "$prefix/tmp/junk" ]; then
        ok "clean_keeps_live: clean-all empties \$PREFIX/tmp but keeps a running work profile"
    else
        fail "clean_keeps_live: profile kept: $([ -d "$profile" ] && echo yes || echo no), other folder removed: $([ -e "$prefix/tmp/junk" ] && echo no || echo yes)"
    fi
    rm -rf "$profile"
}

for check in "$@"; do
    "check_$check"
done
exit "$failed"
