#!/usr/bin/env zsh
# Usage: zsh-snapshot.zsh <out-dir>   — records what an interactive zsh defines, as you and as an AI agent
# Snapshot before and after a dotfiles change, then review with: diff -ru <before-dir> <after-dir>

if [[ $1 == --dump ]]; then
    () {
        local f
        print -r -- "== values"
        for f in AGENT_SHELL LC_ALL LC_CTYPE EDITOR VISUAL HOMEBREW_PREFIX FZF_DEFAULT_COMMAND FZF_ALT_C_COMMAND; do
            print -r -- "$f=${(P)f}"
        done
        local LC_ALL=C
        print -r -- "== functions"
        for f in ${(ko)functions}; do
            print -r -- "--- $f"
            print -r -- "$functions[$f]"
        done
        print -r -- "== aliases"
        print -rl -- ${(o)${(f)"$(alias -L)"}}
        print -r -- "== global and suffix aliases"
        print -rl -- ${(o)${(f)"$(alias -gL; alias -sL)"}}
        print -r -- "== options"
        print -rl -- ${(o)${(f)"$(setopt)"}}
        print -r -- "== parameter names"
        print -rl -- ${(ko)parameters:#(RANDOM|SECONDS|EPOCHSECONDS|EPOCHREALTIME|epochtime|LINENO|_|\?|\$|status|pipestatus|TTYIDLE|ZSH_EXECUTION_STRING|PPID|SHLVL|zsh_eval_context|funcfiletrace|funcsourcetrace|funcstack|functrace|POSH_SESSION_ID)}
        print -r -- "== path"
        print -rl -- $path
        print -r -- "== fpath"
        print -rl -- $fpath
        print -r -- "== hooks"
        print -r -- "precmd: $precmd_functions"
        print -r -- "preexec: $preexec_functions"
        print -r -- "chpwd: $chpwd_functions"
        print -r -- "zshexit: $zshexit_functions"
        print -r -- "== bindkey"
        bindkey -L
        print -r -- "== zstyle"
        zstyle -L
    }
    return 0
fi

out=${1:?usage: zsh-snapshot.zsh <out-dir>}
self=${0:A}
zsh_bin=${commands[zsh]:?zsh not found on PATH}
base=(
    HOME=$HOME
    USER=${USER:-$LOGNAME}
    LOGNAME=${LOGNAME:-$USER}
    TERM=${TERM:-xterm-256color}
    PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
)
[[ -n $TMPDIR ]] && base+=(TMPDIR=$TMPDIR)

umask 077
mkdir -p -- $out || exit 1
cd ~ || exit 1
env -i $base $zsh_bin -i -c "source ${(q)self} --dump" >| $out/human.txt 2>| $out/human.err
env -i $base AI_AGENT=zsh-snapshot $zsh_bin -i -c "source ${(q)self} --dump" >| $out/agent.txt 2>| $out/agent.err
print -r -- "wrote $out/{human,agent}.{txt,err}"
