# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                              ZSH Configuration                            ║
# ╚══════════════════════════════════════════════════════════════════════════╝

# Locale, PATH, agent detection and each tool's PATH and exports, shared with bash
[[ -r ~/.config/shell/env.sh ]] && source ~/.config/shell/env.sh
typeset -U path fpath

# Aliases and small helpers, shared with bash
[[ -r ~/.config/shell/aliases.sh ]] && source ~/.config/shell/aliases.sh

# Tool files register a function that loads a command's completion on its first Tab, and functions to run after compinit
typeset -gA _lazy_completions
typeset -ga _after_compinit

_lazy_load_completions() {
    local cmd=$1; shift
    ${_lazy_completions[$cmd]}
    compdef -d "$cmd"; _complete "$@"
}

# zinit runs this after compinit, after the first prompt; fresh-home-check runs it too, because it has no zinit
_dotfiles_after_compinit() {
    local cmd
    for cmd in ${(k)_lazy_completions}; do
        compdef "_lazy_load_completions $cmd" "$cmd"
    done
    for cmd in $_after_compinit; do
        $cmd
    done
}

# History
HISTFILE=${DOTFILES_HOME:-$HOME}/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt sharehistory
setopt extendedhistory
setopt histignorealldups
setopt histsavenodups
setopt histfindnodups
setopt histexpiredupsfirst
setopt histignorespace

# Options
setopt rcquotes
KEYTIMEOUT=1            # 10ms escape-sequence wait (safe with Ghostty's atomic CSI delivery)

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                              Zinit Plugin Manager                         ║
# ╚══════════════════════════════════════════════════════════════════════════╝

# Skip zinit and heavy plugins inside agent shells (not needed, causes snapshot parse errors); the prompt is in tools/oh-my-posh.sh
if [[ -z "$AGENT_SHELL" ]]; then

# zinit ships uncompiled: sourcing it costs ~24ms, ~19.5ms once zcompiled.
# `zinit self-update` rewrites the sources, which leaves the .zwc files older —
# zsh then ignores them and silently goes back to parsing plain text. So check
# rather than compile once. The check is five stat pairs, well under 1ms.
() {
    local _zdir="${HOME}/.local/share/zinit/zinit.git" f
    for f in $_zdir/zinit.zsh $_zdir/zinit-{side,install,autoload,additional}.zsh; do
        [[ -f $f ]] || continue
        [[ -f $f.zwc && ! $f -nt $f.zwc ]] || zcompile -R -- "$f" 2>/dev/null
    done
}
[[ -f "${HOME}/.local/share/zinit/zinit.git/zinit.zsh" ]] && source "${HOME}/.local/share/zinit/zinit.git/zinit.zsh"

if (( $+functions[zinit] )); then

# Plugins (turbo mode - load after prompt)
zinit wait lucid for \
    OMZL::clipboard.zsh \
    OMZL::completion.zsh \
    OMZL::directories.zsh \
    OMZL::history.zsh \
    OMZP::sudo \
    OMZP::copypath \
    OMZP::copyfile \
    OMZP::copybuffer \
    OMZP::encode64 \
    OMZP::jsontools

# Autosuggestions loaded synchronously (must be ready before first keystroke)
zinit light-mode for zsh-users/zsh-autosuggestions

# Completion init — cached. A full compinit rebuild costs about half a second
# and fires whenever $fpath contents change (brew install/upgrade, zinit update).
# `compinit -C` trusts the existing dump and skips compaudit: ~0.02s. A full run
# happens once a day, which is when new completions get picked up. To force one
# now: `rm ~/.zcompdump && exec zsh`. Skipping compaudit is safe on a single-user
# Mac. The dump is zcompiled so zsh mmaps it instead of parsing 60KB of text.
_zsh_compdump="${DOTFILES_HOME:-$HOME}/.zcompdump"
zicompinit_fast() {
    # extendedglob is OFF in this config; (#q...) needs it, and without it the
    # age test silently falls through to a full rebuild on every single shell.
    setopt localoptions extendedglob
    autoload -Uz compinit
    if [[ -f $_zsh_compdump && -z ${_zsh_compdump}(#qNmh+24) ]]; then
        compinit -C -d "$_zsh_compdump"
    else
        compinit -d "$_zsh_compdump"
    fi
    if [[ ! -f ${_zsh_compdump}.zwc || $_zsh_compdump -nt ${_zsh_compdump}.zwc ]]; then
        zcompile -R -- "$_zsh_compdump" 2>/dev/null
    fi
}

# Heavier plugins deferred — atload wires _self-insert-replace into the chain
zinit wait lucid light-mode for \
    zsh-users/zsh-syntax-highlighting \
    atload"zicompinit_fast; zicdreplay; zle -A self-insert _original-self-insert 2>/dev/null; zle -N self-insert _self-insert-replace" zsh-users/zsh-completions

zinit wait lucid atload'_dotfiles_after_compinit' for zdharma-continuum/null

fi # end zinit check
fi # end AGENT_SHELL check

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                              Key Bindings                                 ║
# ╚══════════════════════════════════════════════════════════════════════════╝

bindkey -e
bindkey '\e\e[C' forward-word         # Legacy word movement
bindkey '\e\e[D' backward-word        # Legacy word movement
bindkey "\e[1~" beginning-of-line     # Home
bindkey "\e[4~" end-of-line           # End

# Highlight selected region
zle_highlight+=(region:standout)

# --- Helpers ---

# Get selected text (handles mark before or after cursor)
_get-selection() {
    local start=$MARK end=$CURSOR
    (( start > end )) && { local t=$start; start=$end; end=$t; }
    REPLY="${BUFFER[$((start+1)),$end]}"
}

# Start or extend selection, then move
_shift-select() {
    ((REGION_ACTIVE)) || zle set-mark-command
    zle "$1"
}

# Deactivate selection, then move
_deselect() { REGION_ACTIVE=0; zle "$1"; }

# --- Selection movements ---

_ss-left()       { _shift-select backward-char; }
_ss-right()      { _shift-select forward-char; }
_ss-word-left()  { _shift-select backward-word; }
_ss-word-right() { _shift-select forward-word; }
_ss-line-left()  { _shift-select beginning-of-line; }
_ss-line-right() { _shift-select end-of-line; }
# up-line / down-line, not up-line-or-history: on a single-line buffer the
# history variants would swap the whole line out from under the selection.
_ss-up()         { _shift-select up-line; }
_ss-down()       { _shift-select down-line; }
_ss-all() {
    MARK=0; CURSOR=${#BUFFER}; REGION_ACTIVE=1
}
for w in _ss-left _ss-right _ss-word-left _ss-word-right _ss-line-left _ss-line-right _ss-up _ss-down _ss-all; do
    zle -N $w
done

# --- Deselect movements ---

_ds-left()       { _deselect backward-char; }
_ds-right()      { _deselect forward-char; }
_ds-word-left()  { _deselect backward-word; }
_ds-word-right() { _deselect forward-word; }
_ds-bol()        { _deselect beginning-of-line; }
_ds-eol()        { _deselect end-of-line; }
_ds-up()         { _deselect up-line-or-history; }
_ds-down()       { _deselect down-line-or-history; }
for w in _ds-left _ds-right _ds-word-left _ds-word-right _ds-bol _ds-eol _ds-up _ds-down; do
    zle -N $w
done

# --- Live cross-session history for autosuggestions ---
# SHARE_HISTORY only imports commands from other sessions at prompt boundaries,
# so an idle, already-open shell keeps suggesting from stale in-memory history
# (e.g. offers an older `brew upgrade` than the one you just ran elsewhere).
# Fix: re-import the history file once per command line before a suggestion is
# computed. We drive this from a custom autosuggest *strategy* (below) rather
# than the self-insert widget, because zsh-autosuggestions re-binds its widgets
# on every precmd (MANUAL_REBIND is unset), which intermittently clobbered the
# turbo atload that wires _self-insert-replace — so the keystroke resync only
# fired sometimes. Strategies are immune to that rebind, so this is reliable.
# `fc -RI` reads only entries appended since the last read, so the cost is nil.
typeset -g _hist_synced_this_line=1
_sync_history_once() {
    (( _hist_synced_this_line )) && return
    _hist_synced_this_line=1
    fc -RI 2>/dev/null   # import entries appended by other sessions
}
_reset_hist_sync() { _hist_synced_this_line=0 }
autoload -Uz add-zsh-hook
add-zsh-hook precmd _reset_hist_sync

# Custom strategy: resync history, then defer to the built-in `history` strategy.
# Active for every fetch (each keystroke); the once-per-line guard keeps `fc -RI`
# to a single call. No-op in agent shells, where autosuggestions isn't loaded.
# NOTE: relies on sync (non-async) fetch — fine here since USE_ASYNC is unset; an
# async fetch would run this in a subshell and the import wouldn't reach the shell.
_zsh_autosuggest_strategy_freshhistory() {
    _sync_history_once
    _zsh_autosuggest_strategy_history "$@"
}
ZSH_AUTOSUGGEST_STRATEGY=(freshhistory)

# --- Type replaces selection ---

_self-insert-replace() {
    _sync_history_once
    if ((REGION_ACTIVE)); then
        zle kill-region
    fi
    zle _original-self-insert 2>/dev/null || zle .self-insert
}
# Register for agent shells only (no autosuggestions there) — paired with the
# `[[ -z "$AGENT_SHELL" ]]` zinit guard above; both must flip together.
# For normal shells, the turbo atload wires this after syntax-highlighting loads
[[ -n "$AGENT_SHELL" ]] && zle -N self-insert _self-insert-replace

# --- Delete with selection awareness ---

_backspace-or-kill() {
    if ((REGION_ACTIVE)); then
        zle kill-region
    else
        zle backward-delete-char
    fi
}
zle -N _backspace-or-kill

_delete-or-kill() {
    if ((REGION_ACTIVE)); then
        zle kill-region
    else
        zle delete-char
    fi
}
zle -N _delete-or-kill

# --- Clipboard (pbcopy, or the per-OS alias from aliases.sh) ---

_copy-to-clipboard() {
    if ((REGION_ACTIVE)); then
        _get-selection
        printf '%s' "$REPLY" | pbcopy
        REGION_ACTIVE=0
    fi
}
zle -N _copy-to-clipboard

_cut-to-clipboard() {
    if ((REGION_ACTIVE)); then
        _get-selection
        printf '%s' "$REPLY" | pbcopy
        zle kill-region
    fi
}
zle -N _cut-to-clipboard

_cut-or-backward-kill-word() {
    if ((REGION_ACTIVE)); then
        zle _cut-to-clipboard
    else
        zle backward-kill-word
    fi
}
zle -N _cut-or-backward-kill-word

# --- Paste replaces selection (bracketed paste from terminal) ---

_bracketed-paste-replace() {
    if ((REGION_ACTIVE)); then
        zle kill-region
    fi
    zle .bracketed-paste
}
zle -N bracketed-paste _bracketed-paste-replace

# --- Undo deselects ---

_undo-deselect() { REGION_ACTIVE=0; zle undo; }
zle -N _undo-deselect

# --- Bindings ---

# Shift+Arrow = select char, or select by line in a multi-line buffer
bindkey '^[[1;2D' _ss-left
bindkey '^[[1;2C' _ss-right
bindkey '^[[1;2A' _ss-up
bindkey '^[[1;2B' _ss-down

# Shift+Opt+Arrow = select word
bindkey '^[[1;4D' _ss-word-left
bindkey '^[[1;4C' _ss-word-right

# Cmd+Shift+Arrow = select to beginning/end of line
bindkey '^[[1;10D' _ss-line-left
bindkey '^[[1;10C' _ss-line-right

# Cmd+A = select all input (via Ghostty CSI)
bindkey '^[[97;9~' _ss-all

# Normal movement deselects
bindkey '^[[D' _ds-left
bindkey '^[[C' _ds-right
bindkey '^[[1;3D' _ds-word-left      # Opt+Left
bindkey '^[[1;3C' _ds-word-right     # Opt+Right
bindkey '^[[A' _ds-up                # Up
bindkey '^[[B' _ds-down              # Down

# Delete
bindkey '^?' _backspace-or-kill      # Backspace (DEL)
bindkey '^H' _backspace-or-kill      # Backspace (BS)
bindkey '^[[3~' _delete-or-kill      # Delete key

# Clipboard (via Ghostty CSI sequences)
bindkey '^[[27;9;99~' _copy-to-clipboard   # Cmd+C (when no terminal selection)
bindkey '^[[120;9~' _cut-to-clipboard   # Cmd+X

# Kill ring (traditional)
bindkey '^W' _cut-or-backward-kill-word  # Ctrl+W = cut selection to clipboard, else delete previous word
bindkey '\ew' _copy-to-clipboard     # Alt+W  = copy to clipboard

# Undo (Cmd+Z via Ghostty CSI, and Ctrl+Z fallback)
bindkey '^[[122;9~' _undo-deselect  # Cmd+Z
bindkey '^Z' _undo-deselect         # Ctrl+Z
