case ${DOTFILES_PHASE:-} in
update)
    _update_add 30 nono _update_nono

    # nono wires its Claude Code plugin by symlinking the pack into the marketplace
    # directory. Claude Code refuses a plugin whose source resolves outside its own
    # marketplace, so replace each declared source with a real copy of the pack.
    # The copy is rewritten on every run, so it never goes stale.
    _nono_materialize_claude_plugins() {
        (( $+commands[nono] && $+commands[jq] )) || return 0
        local line ref ns pname pack_dir mp_dir manifest src rel dest count=0
        for line in "${(@f)$(nono list --installed 2>/dev/null)}"; do
            ref=${line%%[[:space:]]*}
            [[ "$ref" == */* ]] || continue
            ns=${ref%%/*}
            pname=${ref##*/}
            pack_dir="$HOME/.config/nono/packages/$ns/$pname"
            mp_dir="$HOME/.claude/plugins/marketplaces/$ns"
            manifest="$mp_dir/.claude-plugin/marketplace.json"
            [[ -d "$pack_dir/.claude-plugin" && -f "$manifest" ]] || continue
            for src in "${(@f)$(jq -r '.plugins[].source // empty' "$manifest" 2>/dev/null)}"; do
                [[ "$src" == ./* && "$src" != *..* ]] || continue
                rel=${src#./}
                [[ -n "$rel" ]] || continue
                dest="$mp_dir/$rel"
                rm -rf "$dest" || return 1
                cp -R "$pack_dir" "$dest" || return 1
                ((count++))
            done
        done
        (( count > 0 )) && printf '\033[0;90m  Materialized %d nono plugin(s)\033[0m\n' "$count"
        return 0
    }

    # Repair the wiring even when the update fails part way, because a partial
    # update can re-create the symlink and then stop.
    _nono_update_and_materialize() {
        local rc=0
        nono update || rc=$?
        _nono_materialize_claude_plugins || rc=$?
        return $rc
    }

    _update_nono() {
        [[ $mode == update ]] && (( $+commands[nono] )) || return 0
        _update_step "nono Packs" '_nono_update_and_materialize'
    }
    return 0 ;;
launcher) ;;
*) return 0 ;;
esac

# The commands that ~/.local/bin/nclaude, ncco, nccr, nclaude-acp, ncodex, ncodex-acp, nagy, nopc, nopr and nopencode-acp run
(( $+commands[nono] )) || return 0

# Per agent: the flag that skips its own prompts, the hosts it talks to, and its ACP adapter.
# The profile is always <agent>-local, rendered from the shared template .chezmoitemplates/nono-local-profile.
typeset -gA _nono_yolo=(
  claude   --dangerously-skip-permissions
  codex    --dangerously-bypass-approvals-and-sandbox
  agy      --dangerously-skip-permissions
  opencode --auto
)
typeset -gA _nono_default_mode=(
  claude   '--permission-mode auto'
)
typeset -gA _nono_agent_domains=(
  claude   'anthropic.com *.anthropic.com claude.ai *.claude.ai claude.com *.claude.com'
  codex    'openai.com *.openai.com chatgpt.com *.chatgpt.com'
  agy      '*.googleapis.com *.google.com antigravity.google *.antigravity.google *.gstatic.com antigravity-unleash.goog lh3.googleusercontent.com'
  opencode 'opencode.ai *.opencode.ai models.dev'
)
typeset -gA _nono_acp=(
  claude   'npx -y @agentclientprotocol/claude-agent-acp@latest'
  codex    'npx -y @agentclientprotocol/codex-acp@latest'
  opencode 'opencode acp'
)
# What a later agent session outside the sandbox runs or obeys, relative to $HOME. The agent's
# sandbox can write all of it, so after each run the wrapper names what changed.
typeset -gA _nono_watch=(
  claude   '.claude/settings.json .claude/CLAUDE.md .claude/hooks .claude/commands .claude/skills .claude/agents .claude/plugins/cache'
  codex    '.codex/config.toml .codex/hooks.json .codex/AGENTS.md .codex/rules .agents'
  agy      '.gemini/antigravity-cli/settings.json .gemini/antigravity-cli/mcp'
  opencode '.config/opencode/opencode.json .config/opencode/AGENTS.md .config/opencode/plugins .config/opencode/skills'
)
# The opencode pack also grants the Claude and Codex folders
_nono_watch[opencode]+=" ${_nono_watch[claude]} ${_nono_watch[codex]}"

_nono_claude_mcp() {
  [[ -r "$HOME/.claude.json" ]] && (( $+commands[jq] )) || return 0
  jq -cS '[.mcpServers, [.projects[]?.mcpServers]]' "$HOME/.claude.json" 2>/dev/null
}

# ctime, because the sandbox can set a file's mtime back but never its ctime
_nono_report_changes() {
  local agent="$1" since="$2" mcp_before="$3"
  local -a paths=() changed=() parts=()
  local p f
  for p in ${=_nono_watch[$agent]}; do [[ -e "$HOME/$p" ]] && paths+=("$HOME/$p"); done
  (( $#paths )) && for f in "${(@f)$(command find "${paths[@]}" -newerct "$since" \( -type f -o -type l \) \
      ! -path '*/.in_use/*' ! -name .orphaned_at 2>/dev/null)}"; do
    [[ -n "$f" ]] || continue
    if [[ "$f" == "$HOME/.claude/plugins/cache/"*/*/*/* ]]; then
      parts=(${(s:/:)${f#$HOME/.claude/plugins/cache/}})
      f="$HOME/.claude/plugins/cache/${(j:/:)parts[1,3]}"
    fi
    changed+=("${f/#$HOME/~}")
  done
  [[ "$agent" == (claude|opencode) && "$(_nono_claude_mcp)" != "$mcp_before" ]] && changed+=("the MCP servers in ~/.claude.json")
  changed=(${(u)changed})
  (( $#changed )) || return 0
  print -ru2 -- "n$agent: these changed while $agent ran in the sandbox, and a later session outside the sandbox runs or reads them:"
  print -ru2 -l -- "  "${^changed[1,10]}
  (( $#changed > 10 )) && print -ru2 -- "  and $(( $#changed - 10 )) more"
  return 0
}

# Sandboxed agents via nono (OS-level Seatbelt sandbox; no Docker, no VM, no containers).
# Each agent uses its chezmoi-managed `<agent>-local` profile (claude, codex, agy), rendered from the
# shared .chezmoitemplates/nono-local-profile. Claude's extends the signed nolabs-ai/claude
# pack profile (`nono pull nolabs-ai/claude`; the older always-further/claude pack does not parse
# on nono 0.80, so remove it if it is still installed), Codex's nolabs-ai/codex and agy's
# nolabs-ai/antigravity. The profile widens open_urls.allow_origins for browser
# sign-in (OAuth) flows (the agent's own, GitHub, GitLab and Google) — a browser-open
# allowlist, not network access. Employer-specific origins and extra filesystem grants come from
# ~/.config/chezmoi/data.d/*.json (nono_extra_signin_origins / nono_extra_fs_allow), which a work
# dotfiles layer writes. The cwd and real ~/.claude are read-write and Keychain auth
# works, while ~/.ssh, ~/.aws, browser data, and shell configs/history stay denied by default.
# The profile also carries the narrow grants that make the toolchain usable inside the sandbox:
# git (over HTTPS via git-credential-manager; SSH remotes are rewritten to HTTPS by GIT_CONFIG_*),
# glab, gh, dotnet and npm. See the profile template for why each grant is needed.
# Leading --docker, --aws and --k8s (alias --kube) grant the Docker socket, ~/.aws or ~/.kube for
# one run. Each one reaches far outside the sandbox, so each is off by default and separate.
# claude runs as you on the host, so
# --ide reaches the editor on localhost directly (no socat relay). There is no persistent
# sandbox to create/list/delete, so there's no nccl/nccd — each launch just applies kernel rules.
# By default claude runs in auto mode, like outside the sandbox: a classifier checks each risky action
# instead of asking, and nono is the hard boundary underneath. Pass a leading -y/--yolo to bypass prompts for
# that run (claude --dangerously-skip-permissions); nono still blocks secrets and any write
# outside the granted paths. Leading args that are existing dirs (optionally `path:ro`) become
# extra grants (rw, or ro for :ro); the rest is forwarded to claude.
# `nclaude -h` / `ncco -h` / `nccr -h` prints the full flag + capability reference.
_nclaude_help() {
  local self="${1:-nclaude}" agent="${2:-claude}"
  print -r -- "\
${self} — ${agent} in a nono Seatbelt sandbox (kernel-enforced; no Docker/VM).

USAGE
  ${self} [-y|--yolo] [--docker] [--aws] [--k8s] [DIR|DIR:ro ...] [${agent} args ...]

LEADING FLAGS (must come before any ${agent} args; any order)
  -y, --yolo    Run ${agent} with ${_nono_yolo[$agent]}, i.e. no per-action
                prompts. nono remains the hard boundary: secrets stay blocked and
                writes outside granted paths still fail. Default is ${agent}'s own
                mode (auto mode for claude), so nono is defense in depth rather
                than the only gate.
  --docker      Grant the Docker Desktop socket and ~/.docker. Off by default,
                because the socket can start a container that mounts any host
                folder, which gets around every other limit of the sandbox.
  --aws         Grant RW ~/.aws — live cloud credentials. Off by default.
  --k8s         Grant RW ~/.kube — live cluster credentials. Off by default.
                (--kube is accepted as an alias.)
  --acp         Run the agent's ACP adapter instead, for an editor that hosts
                agents over ACP (JetBrains AI Assistant, Zed). nono prints nothing,
                because ACP uses stdin and stdout. Claude and Codex have adapters:
                nclaude-acp and ncodex-acp are this mode.
  --netlock     ON BY DEFAULT — you do not need to pass this; it is accepted for
                clarity. Egress is default-deny: nono runs a supervising proxy and
                only the allowlist connects. Kernel-enforced, not just proxy env
                vars — verified that bypassing HTTP_PROXY and a raw socket to a
                bare IP are both blocked. Generic hosts are built in; private ones
                go in ~/.config/nono/netlock-domains, one per line.
  --no-netlock  Turn the lockdown OFF for one run: unrestricted egress, i.e. the
                agent can reach any host. Use when something is blocked and you
                need to get unstuck; then add the host to netlock-domains so you do
                not need this again. --net-unlock is accepted as an alias.
                The statusline shows 🔒 nono·net-open when you are in this mode,
                because unrestricted egress is the exception worth seeing.

                To find WHAT was blocked instead of guessing from a timeout:
                  nono audit list --today
                  nono audit show <id>
                It logs each denial as e.g. \"deny connect host:443
                (reason=host ... is not in the allowlist)\".

                Authenticated git, curl, npm, NuGet and the Anthropic API work
                under it. If git says \"could not read Username\", the cached
                credential is stale, with or without netlock. The sandbox cannot
                refresh it, so run any git command once outside the sandbox.

                Raises the bar, does not close the hole — an allowed host such as
                github is itself an egress channel.
  --selftest    Run the verification suite inside the sandbox and exit: git config,
                authenticated git, signed commit, gpg private keys still sealed,
                ~/.ssh still sealed, glab, gh, dotnet, npm, docker and docker pull
                (with --docker), global gitignore, and egress lockdown. Re-run it after a nono
                upgrade, a profile edit, or a Docker/credential change — those are
                what silently break the sandbox.
  --dry         Print the resolved profile, grants and command, apply the sandbox,
                then exit without starting ${agent}. For checking what a flag
                combination actually grants.
  -h, --help    Show this text.

  --docker, --aws and --k8s are independent and compose. Each one needs
  bypass_protection on top of its grant, since deny_credentials blocks the
  directory outright — the wrapper handles that for you.

EXTRA PATH GRANTS
  Leading args that are existing directories become extra sandbox grants:
    DIR         read+write
    DIR:ro      read-only
  The cwd is always granted read+write (--allow-cwd). Everything after the first
  non-directory / flag arg is forwarded to ${agent} untouched.

  Cross-repo work needs an explicit grant, e.g. a shared library you only read:
    ncco ~/Projects/some-shared-lib:ro

GIT WORKTREES AND SUBDIRECTORIES
  Handled automatically. A worktree's .git is a file pointing outside the worktree,
  and from a subdir the repo's .git sits above cwd — both would otherwise fail with
  \"fatal: not a git repository\". The wrapper grants the main repo's git dir (that
  alone, not the whole main checkout) whenever it falls outside cwd. Pass the repo
  root explicitly if you want the rest of the tree too.

VARIANTS
  nclaude       Claude Code, plain
  ncco          + --ide  (reaches your editor on localhost directly, no relay)
  nccr          + --ide --resume
  ncodex        Codex CLI
  nagy          Antigravity CLI
  nclaude-acp, ncodex-acp   the ACP adapters, for an editor

WHAT WORKS INSIDE THE SANDBOX (${agent}-local, verified by running each tool)
  git           over HTTPS via git-credential-manager + Keychain. SSH remotes are
                rewritten to HTTPS by GIT_CONFIG_* env, so existing git@ clones work.
                Global ignores from ~/.config/git/ignore are honored.
  git commit    signed. commit.gpgsign is on globally, so this would otherwise fail
                with \"gpg: signing failed: No secret key\". The sandbox gets pubring,
                gpg.conf, trustdb and connect() on the HOST gpg-agent socket — the
                agent does the signing, so ~/.gnupg/private-keys-v1.d stays DENIED.
  glab, gh      read their tokens from their own config dirs.
  dotnet        SDKs and global tools read-only; ~/.dotnet/.dotnet, ~/.nuget and
                ~/.aspnet RW. Build, restore and global tools work.
  npm           ~/.npm RW (without it npm install fails outright).
  docker        only with --docker: the Docker Desktop socket and ~/.docker.
  MCP servers   remote HTTP+OAuth, creds in Keychain.

STILL DENIED (by design)
  ~/.ssh        no private keys, no ssh-agent. Use HTTPS; see git above.
  ~/.gnupg/private-keys-v1.d   signing goes through the host agent, never the keys.
  docker        unless --docker.
  ~/.aws        unless --aws.
  ~/.kube       unless --k8s.
  ~/.terraform.d  not granted; ask if you need terraform in the sandbox.
  browser data, shell configs + history, other credential stores.

KNOWN NOISE
  Every PATH-resolved exec logs one denied read of ~/.local/share/chezmoi. Nothing
  fails; the dotfiles repo is deliberately ungranted. Absolute-path exec is silent.

AFTER EACH RUN
  The wrapper lists the agent files that changed during the run and that a later
  session outside the sandbox runs or reads: settings, hooks, instructions, skills,
  plugins and MCP servers. A change that you did not make can be a planted hook.

DIAGNOSING A DENIAL
  nono why --profile ${agent}-local --path <PATH> --op <read|write|readwrite>

PROFILE  ~/.config/nono/profiles/${agent}-local.json
  chezmoi-managed: the grants for every agent are in .chezmoitemplates/nono-local-profile
  in ~/.local/share/chezmoi, and dot_config/nono/profiles/${agent}-local.json.tmpl adds
  the agent's own. Then chezmoi apply. Do not edit the rendered file."
}

# Repeatable verification of everything the sandbox is supposed to be able to do. Everything in this
# file was originally verified by hand; this makes it re-runnable after a nono upgrade, a profile
# change, or a Docker/credential change, because those are exactly what silently break it.
_nclaude_selftest() {
  local profile="$1" docker="$2"; shift 2
  local dir="/tmp/nono-selftest-$(id -u)"; mkdir -p "$dir" 2>/dev/null
  local probe="$dir/nono-selftest-$$.sh"
  cat > "$probe" <<'PROBE'
p() { printf '  %-14s %s\n' "$1" "$2"; }
fail=0
ok()  { p "$1" "PASS  $2"; }
bad() { p "$1" "FAIL  $2"; fail=1; }

git config --get user.email >/dev/null 2>&1 \
  && ok git-config || bad git-config "cannot read user.email (~/.gitconfig.local not granted?)"

url=$(git remote get-url origin 2>/dev/null)
if [ -z "$url" ]; then p git-auth "SKIP  (cwd has no origin remote)"
elif git ls-remote "$url" HEAD >/dev/null 2>&1; then ok git-auth
else bad git-auth "ls-remote failed - stale GCM credential? run a git command on the HOST"
fi

d=$(mktemp -d 2>/dev/null) || d=""
if [ -n "$d" ] && git init -q "$d" 2>/dev/null; then
  : > "$d/f"; git -C "$d" add f 2>/dev/null
  # Signing can be off globally, so the test turns it on for its own commit
  if ! git config --get user.signingkey >/dev/null 2>&1; then p gpg-sign "SKIP  (no user.signingkey on this machine)"
  elif git -C "$d" -c commit.gpgsign=true commit -q -m selftest 2>/dev/null && \
     [ "$(git -C "$d" log -1 --format=%G? 2>/dev/null)" = "G" ]; then ok gpg-sign
  else bad gpg-sign "commit unsigned/failed - gpg-agent socket or trustdb grant"
  fi
  git -C "$d" check-ignore --no-index -q .worktrees/x 2>/dev/null \
    && ok gitignore || bad gitignore "global ~/.config/git/ignore not honoured"
  rm -rf "$d"
else p gpg-sign "SKIP  (mktemp failed)"
fi

ls "$HOME/.gnupg/private-keys-v1.d" >/dev/null 2>&1 \
  && bad gpg-privkeys "READABLE - must stay denied" || ok gpg-privkeys "(sealed)"
ls "$HOME/.ssh" >/dev/null 2>&1 \
  && bad ssh-denied "READABLE - must stay denied" || ok ssh-denied "(sealed)"

glab auth status >/dev/null 2>&1 && ok glab   || bad glab
gh   auth status >/dev/null 2>&1 && ok gh     || bad gh
dotnet --version >/dev/null 2>&1 && ok dotnet "($(dotnet --version 2>/dev/null))" || bad dotnet
if [ -d "$HOME/.dotnet/tools" ]; then
  if touch "$HOME/.dotnet/tools/.nono-selftest" 2>/dev/null; then
    rm -f "$HOME/.dotnet/tools/.nono-selftest"
    bad dotnet-tools "WRITABLE - a planted tool would run outside the sandbox later"
  else ok dotnet-tools "(read-only)"
  fi
fi
npm  ping >/dev/null 2>&1 && ok npm || bad npm "(registry unreachable)"
if [ "$NONO_SELFTEST_DOCKER" = 1 ]; then
  docker ps >/dev/null 2>&1 && ok docker || bad docker "(is Docker Desktop running?)"
  docker pull alpine:latest >/dev/null 2>&1 && ok docker-pull || bad docker-pull "(credsStore helper)"
else
  docker ps >/dev/null 2>&1 && bad docker-denied "REACHABLE without --docker" || ok docker-denied "(sealed)"
fi

python3 - <<'LOOP' 2>/dev/null || bad loopback "python3 unavailable, not checked"
import socket, threading, sys
srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 18099)); srv.listen(1)
threading.Thread(target=srv.accept, daemon=True).start()
try:
    socket.create_connection(("127.0.0.1", 18099), timeout=5)
    print("  loopback       PASS  (--ide, JetBrains MCP, local services)")
except Exception as e:
    print("  loopback       FAIL  blocked - needs network.open_port [0] under netlock"); sys.exit(1)
LOOP
[ $? -eq 0 ] || fail=1

locked=unknown
if [ -n "$NONO_CAP_FILE" ] && command -v jq >/dev/null 2>&1; then
  locked=$(jq -r 'if ((.allowed_domains|length)>0) then "yes" else "no" end' "$NONO_CAP_FILE" 2>/dev/null)
fi
if curl -sS -o /dev/null -m 10 https://example.com >/dev/null 2>&1; then reach=yes; else reach=no; fi
case "$locked:$reach" in
  yes:no)  ok  egress "locked, unlisted host blocked" ;;
  yes:yes) bad egress "locked but an unlisted host was REACHABLE" ;;
  no:*)    p   egress "OPEN  (--no-netlock) unlisted host reachable=$reach" ;;
  *)       p   egress "UNKNOWN (no NONO_CAP_FILE or no jq)" ;;
esac
PROBE
  # A work layer adds checks for its own tools here, written with the same ok and bad functions
  local extra_check
  for extra_check in "$HOME"/.config/nono/selftest.d/*.sh(N); do
    cat "$extra_check" >> "$probe"
  done
  cat >> "$probe" <<'PROBE'

if [ "$fail" -eq 0 ]; then printf '\n  all checks passed\n'
else printf '\n  FAILURES above. For a blocked host: nono audit list --today, then\n  nono audit show <id> - it names the exact host and reason.\n'
fi
exit "$fail"
PROBE
  print -r -- "nono selftest - profile $profile, cwd $PWD"
  nono run --profile "$profile" --allow-cwd "$@" -- env NONO_SELFTEST_DOCKER="$docker" sh "$probe"
  local rc=$?
  rm -f "$probe"
  return $rc
}

_nono_agent_impl() {
  local agent="$1" extra_flags="$2"; shift 2
  local profile="${agent}-local"
  local perm_flag="${_nono_default_mode[$agent]}"  # default: auto mode for claude, the agent's own mode otherwise
  local netlock=1 dry=0 selftest=0 acp=0 docker=0  # egress locked down by DEFAULT; --no-netlock opts out
  local -a grants=()
  local dockerdata
  # Leading flags, any order. --docker/--aws/--k8s are opt-in grants: deny_credentials blocks each
  # dir, so each needs --bypass-protection alongside its --allow.
  while :; do
    case "$1" in
      -y|--yolo)    perm_flag="${_nono_yolo[$agent]}"; shift ;;          # nono is still the boundary
      --docker)
        docker=1
        grants+=(--allow "$HOME/.docker" --bypass-protection "$HOME/.docker"
                 --allow-unix-socket "$HOME/.docker/run/docker.sock")
        # A registry operation runs the Docker Desktop credential helper, which reads these
        for dockerdata in "$HOME/Library/Containers/com.docker.docker" "$HOME/Library/Group Containers/group.com.docker"; do
          [[ -d "$dockerdata" ]] && grants+=(--read "$dockerdata")
        done
        shift ;;
      --aws)        grants+=(--allow "$HOME/.aws"  --bypass-protection "$HOME/.aws");  shift ;;
      --k8s|--kube) grants+=(--allow "$HOME/.kube" --bypass-protection "$HOME/.kube"); shift ;;
      --netlock)    netlock=1; shift ;;                                   # default; accepted for clarity
      --no-netlock|--net-unlock) netlock=0; shift ;;                      # unrestricted egress, this run
      --dry)        dry=1; shift ;;
      --selftest)   selftest=1; shift ;;
      --acp)        acp=1; shift ;;
      -h|--help)    _nclaude_help "${funcstack[2]:-n$agent}" "$agent"; return 0 ;;
      *) break ;;
    esac
  done
  while [[ -n "$1" && "$1" != -* ]]; do
    local wpath="$1" ro=0
    [[ "$1" == *:ro ]] && { ro=1; wpath="${1%:ro}"; }
    [[ -d "$wpath" ]] || break
    if (( ro )); then grants+=(--read "${wpath:A}"); else grants+=(--allow "${wpath:A}"); fi
    shift
  done
  # Git needs more than cwd when cwd is not the repo root:
  #   - From a SUBDIR, repo discovery chdir("..")s upward, so the ancestors must be granted or git
  #     fails with "fatal: unable to get current working directory". Granting just .git is NOT
  #     enough — git cannot walk up to find it. Hence --show-toplevel (the working-tree root).
  #   - In a WORKTREE, .git is a FILE pointing at <main-repo>/.git/worktrees/<name>, which lives
  #     outside the worktree entirely. Hence --git-common-dir.
  # Grant whichever of the two falls outside cwd; both are skipped when cwd is already the root.
  local -a gitpaths=()
  local p
  for p in "$(git rev-parse --path-format=absolute --show-toplevel 2>/dev/null)" \
           "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; do
    [[ -n "$p" && -d "$p" ]] || continue
    [[ "$p" == "$PWD" || "$p" == "$PWD"/* ]] && continue      # already covered by --allow-cwd
    (( ${gitpaths[(Ie)${p:A}]} )) && continue                 # dedupe
    gitpaths+=("${p:A}")
  done
  for p in "${gitpaths[@]}"; do grants+=(--allow "$p"); done
  # --netlock: default-deny egress. Any --allow-domain puts nono in supervised proxy mode, so this
  # list is the entire allowlist. Entries are CONNECT tunnels, so TLS is not intercepted. Hosts that
  # would name an employer come from the untracked ~/.config/nono/netlock-domains instead.
  # This raises the bar, it does not close the hole: an allowed host such as github is itself an
  # egress channel. No interactive credential flow works in the sandbox, so log in on the host.
  if (( netlock )); then
    local -a domains=(
      ${=_nono_agent_domains[$agent]}
      github.com '*.github.com' '*.githubusercontent.com'
      gitlab.com '*.gitlab.com'
      '*.context7.com'
      nuget.org '*.nuget.org' registry.npmjs.org '*.npmjs.org'
      '*.dotnet.microsoft.com' aka.ms '*.azureedge.net'
      '*.docker.io' '*.docker.com'
      formulae.brew.sh '*.brew.sh'
    )
    local extra="$HOME/.config/nono/netlock-domains"
    # `command grep` on purpose: grep is aliased to rg in .personal.zsh, and `rg -vE` parses
    # -E as --encoding, silently yielding nothing -- which drops every private host from the
    # allowlist while looking like it worked.
    [[ -r "$extra" ]] && domains+=(${(f)"$(command grep -vE '^[[:space:]]*(#|$)' "$extra")"})
    local d; for d in $domains; do grants+=(--allow-domain "$d"); done
  fi

  # No --rollback flag on purpose: `nono rollback restore` ignores rollback.exclude_patterns and
  # stops at the 2 GiB budget, so a snapshot of these grants can never be restored.
  # If a future nono fixes restore, wire it up as:
  #     grants+=(--rollback --rollback-exclude "claude-$(id -u)")
  # After the netlock block on purpose: dispatching from the flag loop would test an
  # unlocked sandbox instead of the real default, which is exactly what it caught first run.
  if (( selftest )); then _nclaude_selftest "$profile" "$docker" "${grants[@]}"; return $?; fi

  if (( dry )); then                              # show the resolved sandbox, do not launch the agent
    print -r -- "profile: $profile   cwd: $PWD"
    print -r -- "would run: nono run --profile $profile --allow-cwd ${grants[*]} -- $agent ${perm_flag} ${extra_flags} $*"
    nono run --profile "$profile" --allow-cwd "${grants[@]}" -- /usr/bin/true
    return $?
  fi
  # One second back, because find compares whole seconds
  local since mcp_before rc
  zmodload zsh/datetime
  strftime -s since '%Y-%m-%d %H:%M:%S' $(( EPOCHSECONDS - 1 ))
  [[ "$agent" == (claude|opencode) ]] && mcp_before=$(_nono_claude_mcp)
  if (( acp )); then
    if [[ -z "${_nono_acp[$agent]}" ]]; then
      print -ru2 -- "n$agent: $agent has no ACP adapter"
      return 1
    fi
    # The editor does not say which folder it starts agents in; granting $HOME or / would open everything
    if [[ "$PWD" == "$HOME" || "$PWD" == / ]]; then
      print -ru2 -- "n$agent-acp: refusing to grant $PWD to the sandbox; the editor must start it in a project folder"
      return 1
    fi
    nono run --profile "$profile" --allow-cwd --silent --startup-timeout 0 "${grants[@]}" \
      -- ${=_nono_acp[$agent]}
    rc=$?
  else
    nono run --profile "$profile" --allow-cwd "${grants[@]}" \
      -- "$agent" ${=perm_flag} ${=extra_flags} "$@"
    rc=$?
  fi
  _nono_report_changes "$agent" "$since" "$mcp_before"
  return $rc
}

nclaude() { _nono_agent_impl claude ""               "$@"; }
ncco()    { _nono_agent_impl claude "--ide"          "$@"; }
nccr()    { _nono_agent_impl claude "--ide --resume" "$@"; }
nclaude-acp() { _nono_agent_impl claude "" --acp "$@"; }
ncodex()  { _nono_agent_impl codex ""                "$@"; }
ncodex-acp() { _nono_agent_impl codex "" --acp "$@"; }
nagy()    { _nono_agent_impl agy ""                  "$@"; }
# Without --standalone, opencode hands the work to its background server, which runs outside the sandbox
nopc()    { _nono_agent_impl opencode "--standalone"            "$@"; }
nopr()    { _nono_agent_impl opencode "--standalone --continue" "$@"; }
nopencode-acp() { _nono_agent_impl opencode "" --acp "$@"; }
