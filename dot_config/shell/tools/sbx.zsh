# The commands that ~/.local/bin/scc*, sclaude, scodex and sopc run
[[ ${DOTFILES_PHASE:-} == launcher ]] || return 0
(( $+commands[sbx] )) || return 0

# Sandboxed agent (Docker Sandboxes). Leading args that are existing directories (optionally
# `path:ro`) become extra workspaces; the rest is forwarded to the agent. Each unique
# (agent, cwd, extras...) set gets its own sandbox, named <agent>-<folder>-<cwd id>[-<extras id>],
# so a later run finds it by name and two project dirs with the same basename don't collide.
#   claude: ~/sbx-kits/claude-config kit; cwd rw + ~/.claude ro + projects rw for memory.
#   codex, opencode: cwd rw; the global rules file is copied in on every start. Codex signs in
#           through the sbx `openai` secret, so the ChatGPT token stays on the host.
typeset -gA _sbx_rules=(
  codex    .codex/AGENTS.md
  opencode .config/opencode/AGENTS.md
)

_sbx_agent_impl() {
  local agent="$1" extra_flags="$2"; shift 2

  # Leading wrapper flags (before any workspace dirs): --recreate/--fresh rebuilds this workspace's
  # sandbox; --list/--ls lists it; --delete/--rm removes it; --force/-f skips sbx's rm confirmation.
  # sccl/sccd wrap --list/--delete (and accept --force).
  local recreate=0 delete=0 list=0 force=0
  while [[ "$1" == --recreate || "$1" == --fresh || "$1" == --list || "$1" == --ls || "$1" == --delete || "$1" == --rm || "$1" == --force || "$1" == -f ]]; do
    case "$1" in
      --recreate|--fresh) recreate=1 ;;
      --list|--ls)        list=1 ;;
      --delete|--rm)      delete=1 ;;
      --force|-f)         force=1 ;;
    esac
    shift
  done

  if (( list || delete )); then
    local -a names=("${(@f)$(_sbx_ws_sandboxes)}")
    names=(${names:#})                      # drop empty lines
    if (( ${#names} == 0 )); then echo "No sandboxes for $PWD" >&2; return 0; fi
    if (( list )); then
      # Keep sbx's native table, filtered to this workspace's sandboxes (header + matching rows).
      sbx ls | awk -v set=" ${(j: :)names} " 'NR==1 || index(set, " " $1 " ")'
      return 0
    fi
    echo "Sandboxes for $PWD:" >&2
    printf '  - %s\n' "${names[@]}" >&2
    local -a rmflags=(); (( force )) && rmflags=(--force)
    sbx rm "${rmflags[@]}" "${names[@]}"    # sbx prompts to confirm each unless --force
    return
  fi

  local -a resolved_extras=()
  while [[ -n "$1" && "$1" != -* ]]; do
    local ro="" wpath="$1"
    [[ "$1" == *:ro ]] && { ro=":ro"; wpath="${1%:ro}"; }
    [[ -d "$wpath" ]] || break
    resolved_extras+=("${wpath:A}${ro}")
    shift
  done

  local n="$agent-$(_sbx_ws_prefix)"
  (( ${#resolved_extras} )) && n+="-$(_sbx_id "${(j: :)resolved_extras}")"

  local -a create_args=("$agent" .)
  [[ $agent == claude ]] && create_args=(--kit ~/sbx-kits/claude-config claude . "$HOME/.claude:ro" "$HOME/.claude/projects")

  local exists=0
  sbx ls -q 2>/dev/null | grep -qxF -- "$n" && exists=1
  if (( recreate && exists )); then
    echo "Recreating: removing sandbox $n..." >&2
    sbx rm --force "$n" >/dev/null 2>&1
    exists=0
  fi

  if (( ! exists )); then
    echo "Creating sandbox $n for $PWD${resolved_extras:+ (+${#resolved_extras[@]} extra)}..." >&2
    sbx create --no-progress --name "$n" "${create_args[@]}" "${resolved_extras[@]}" >/dev/null || return $?
    [[ $agent == claude ]] && _sbx_claude_credential "$n"
    [[ $agent == codex ]] && ! sbx secret ls 2>/dev/null | grep -qw openai \
      && echo "scodex: no sbx openai secret; run 'sbx secret set -g openai' once, then scodex --recreate" >&2
  fi

  local rules="${_sbx_rules[$agent]}"
  [[ -n "$rules" && -f "$HOME/$rules" ]] \
    && sbx exec -i "$n" -u 1000 sh -c 'mkdir -p "$HOME/${1%/*}" && cat > "$HOME/$1"' sh "$rules" \
       < "$HOME/$rules" >/dev/null 2>&1

  sbx run --name "$n" -- ${=extra_flags} "$@"
}

# Auto-load Claude auth so the in-container claude starts authenticated (refreshes in-container).
# OS-agnostic extraction: credentials file (Linux + Windows, honoring CLAUDE_CONFIG_DIR) first,
# macOS Keychain fallback. The file branch covers WSL/Git-Bash too (wherever $HOME resolves).
_sbx_claude_credential() {
  local n="$1" cred="" cfg_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  if [ -f "$cfg_dir/.credentials.json" ]; then
    cred=$(cat "$cfg_dir/.credentials.json")
  elif command -v security >/dev/null 2>&1; then
    cred=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
  fi
  if [ -n "$cred" ]; then
    printf '%s' "$cred" | sbx exec -i "$n" -u 1000 sh -c \
      'umask 077; mkdir -p "$HOME/.claude" && cat > "$HOME/.claude/.credentials.json"' \
      >/dev/null 2>&1 \
      || echo "sclaude: credential injection failed; you may be prompted to log in" >&2
  else
    echo "sclaude: no host Claude credential found; log in inside the sandbox once" >&2
  fi
}

_sbx_id() { print -rn -- "$1" | cksum | cut -d' ' -f1 }

# <folder>-<cwd id>: the part of the name that every agent's sandbox for this folder shares
_sbx_ws_prefix() {
  local base="${PWD:t}"
  print -r -- "${${base//[^A-Za-z0-9.-]/-}:-root}-$(_sbx_id "$PWD")"
}

# Every agent's sandboxes for the current dir, with or without extra workspaces
_sbx_ws_sandboxes() {
  local prefix="$(_sbx_ws_prefix)" n
  for n in ${(f)"$(sbx ls -q 2>/dev/null)"}; do
    [[ $n == *-$prefix || $n == *-$prefix-<-> ]] && print -r -- "$n"
  done
}

sclaude() { _sbx_agent_impl claude ""                "$@"; }  # 1st arg: --recreate / --list / --delete
scco()    { _sbx_agent_impl claude "--ide"           "$@"; }
sccr()    { _sbx_agent_impl claude "--ide --resume"  "$@"; }
sccl()    { _sbx_agent_impl claude "" --list         "$@"; }  # list this workspace's sandbox(es), every agent
sccd()    { _sbx_agent_impl claude "" --delete       "$@"; }  # remove this workspace's sandbox(es), with confirmation
scodex()  { _sbx_agent_impl codex  ""                "$@"; }
sopc()    { _sbx_agent_impl opencode ""              "$@"; }
