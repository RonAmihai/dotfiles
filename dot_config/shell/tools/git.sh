case ${DOTFILES_PHASE:-} in
aliases)
    command -v git >/dev/null 2>&1 || return 0
    alias git-submodules-init='git submodule update --init --recursive'
    alias git-submodules-update='git submodule update --remote --merge --recursive'
    alias gch='git-checkout-latest'
    alias gchu='git-unlock && git-checkout-latest'
    alias gnuke='git-nuke'
    return 0 ;;
esac
[ -n "${ZSH_VERSION:-}" ] || return 0

case $DOTFILES_PHASE in
setup)
    # Oh My Zsh's git aliases (gst, gco and the rest), loaded after the first prompt
    [[ -z $AGENT_SHELL ]] && (( $+functions[zinit] )) && zinit wait lucid for OMZP::git
    return 0 ;;
launcher) ;;
*) return 0 ;;
esac

# The commands that ~/.local/bin/git-* run
(( $+commands[git] )) || return 0

_git_default_branch() {
  local head b
  head=$(git symbolic-ref -q --short refs/remotes/origin/HEAD) && { print -r -- "${head#origin/}"; return 0; }
  for b in main master; do
    git show-ref -q "refs/heads/$b" "refs/remotes/origin/$b" && { print -r -- "$b"; return 0; }
  done
  return 1
}

git-checkout-latest() {
  local branch=$1
  [[ -n $branch ]] || branch=$(_git_default_branch) || {
    print -ru2 -- "git-checkout-latest: no branch given, and no origin/HEAD, main or master found"
    return 1
  }
  local stash_before=$(git rev-parse -q --verify refs/stash)
  if ! git diff --quiet || ! git diff --cached --quiet; then
    git stash push -m "git-checkout-latest auto-stash"
  fi
  git checkout "$branch" && git pull && git submodule update --init --recursive --force
  # stash push exits 0 without saving when only a submodule pointer moved
  if [[ "$(git rev-parse -q --verify refs/stash)" != "$stash_before" ]]; then
    echo "\nRestoring stashed changes..."
    git stash pop
  fi
}

git-nuke() {
  local root
  root=$(git rev-parse --show-toplevel) || return
  git -C "$root" status --short
  read -q "REPLY?Discard all changes and untracked files in ${root/#$HOME/~}? [y/N] " || { print; return 1; }
  print
  git-unlock "$root" &&
    git -C "$root" reset --hard &&
    git -C "$root" clean -fd &&
    git -C "$root" submodule update --init --recursive --force
}

# Remove stale git lock files (index.lock, HEAD.lock, config.lock, refs/**/*.lock, ...)
# left behind when a git op dies mid-write — including submodule git dirs (.git/modules/*).
# Scoped to *.lock files living INSIDE a .git directory, so it can never delete dependency
# manifests like package-lock.json, Cargo.lock, poetry.lock, or .terraform.lock.hcl.
# Usage: git-unlock [-n|--dry-run] [path ...]   (path defaults to the current dir)
git-unlock() {
    local dry_run=false
    local -a paths
    while (( $# )); do
        case "$1" in
            -n|--dry-run) dry_run=true ;;
            -h|--help)
                echo "usage: git-unlock [-n|--dry-run] [path ...]   (clears stale *.lock files inside .git dirs; path defaults to current dir)"
                return 0 ;;
            --) shift; paths+=("$@"); break ;;
            -*) echo "git-unlock: unknown option: $1" >&2; return 2 ;;
            *)  paths+=("$1") ;;
        esac
        shift
    done
    (( ${#paths} )) || paths=("$PWD")

    local root lock count=0
    for root in "${paths[@]}"; do
        if [[ ! -d "$root" ]]; then
            echo "git-unlock: not a directory: $root" >&2
            continue
        fi
        # *.lock files anywhere inside a .git directory (covers submodule .git/modules/*)
        local -a locks=("${(0)$(find "$root" -type f -path '*/.git/*' -name '*.lock' -print0 2>/dev/null)}")
        for lock in "${locks[@]}"; do
            [[ -n "$lock" ]] || continue
            if $dry_run; then
                echo "would remove  $lock"
            elif rm -f -- "$lock"; then
                echo "removed  $lock"
            else
                echo "git-unlock: failed to remove $lock" >&2
                continue
            fi
            (( count++ ))
        done
    done

    local noun=locks; (( count == 1 )) && noun=lock
    if $dry_run; then
        echo "${count} git ${noun} would be removed"
    else
        echo "${count} git ${noun} removed"
    fi
    return 0
}

# Human-readable size from a KB count. Exists so sizes come from the one `du -sk` we already
# ran, instead of paying for a second `du -sh` walk per worktree just to get the formatting.
_gwt_size() {
    local -i kb=$1
    if   (( kb >= 1048576 )); then printf '%.1fG' $(( kb / 1048576.0 ))
    elif (( kb >= 1024    )); then printf '%.0fM' $(( kb / 1024.0 ))
    else                           printf '%dK'   "$kb"
    fi
}

# Bulk-remove git worktrees found under a path, and tell git about it afterwards.
# Usage: git-worktrees-remove [-n|--dry-run] [-y|--yes] [--depth N] [--no-check] [path ...]
#
# Two non-obvious things drive the shape of this, both learned the hard way:
#   1. DETECTION. A submodule checked out inside a worktree has its own .git FILE pointing at
#      <repo>/.git/worktrees/<name>/modules/<sub>. So "does the gitdir path contain
#      .git/worktrees/" counts every submodule checkout as a worktree in its own right — which
#      double-counts its bytes (they are already inside the parent worktree), invents phantom
#      container dirs, and makes removal order matter. A real worktree registration sits
#      DIRECTLY under .git/worktrees/, so the registration's parent must be named exactly
#      "worktrees".
#   2. PRUNING. rm -rf deletes the checkout but leaves <repo>/.git/worktrees/<name> behind, so
#      `git worktree list` reports the path as "prunable" forever and `git worktree add` refuses
#      to reuse the name. One `git worktree prune` per affected repo is what actually finishes
#      the job — cheaper than 1 `git worktree remove` per worktree, and it also sweeps stale
#      registrations left by earlier runs.
# Branches are deliberately left alone, exactly as `git worktree remove` leaves them.
git-worktrees-remove() {
    local dry_run=false assume_yes=false check=true
    local depth=6
    local -a paths
    while (( $# )); do
        case "$1" in
            -n|--dry-run) dry_run=true ;;
            -y|--yes)     assume_yes=true ;;
            --no-check)   check=false ;;
            --depth)
                shift
                [[ -n "${1:-}" ]] || { print -ru2 -- "git-worktrees-remove: --depth needs a number"; return 2; }
                depth="$1" ;;
            --depth=*)    depth="${1#--depth=}" ;;
            -h|--help)
                print -r -- "usage: git-worktrees-remove [-n|--dry-run] [-y|--yes] [--depth N] [--no-check] [path ...]

  Removes every git worktree found under each path (default: the current dir), then runs
  \`git worktree prune\` on each affected repo so no stale registrations are left behind.
  Branches are never touched.

    -n, --dry-run   list what would be removed, then exit
    -y, --yes       skip the confirmation prompt
        --depth N   how deep to search for worktrees (default 6)
        --no-check  skip the uncommitted/unpushed scan (faster, but no guardrail)"
                return 0 ;;
            --) shift; paths+=("$@"); break ;;
            -*) print -ru2 -- "git-worktrees-remove: unknown option: $1"; return 2 ;;
            <->) print -ru2 -- "git-worktrees-remove: depth is a flag now — use --depth $1"; return 2 ;;
            *)  paths+=("$1") ;;
        esac
        shift
    done
    [[ "$depth" == <-> ]] || { print -ru2 -- "git-worktrees-remove: --depth must be a number, got: $depth"; return 2; }
    (( ${#paths} )) || paths=("$PWD")
    local p
    for p in "${paths[@]}"; do
        [[ -d "$p" ]] || { print -ru2 -- "git-worktrees-remove: not a directory: $p"; return 2; }
    done

    # A worktree checkout is marked by a .git FILE (a dir means a main checkout). obj/bin/.venv
    # are pruned purely to keep the walk off build output; no worktree root can hide under them.
    local -a candidates=("${(0)$(find "${paths[@]}" -maxdepth "$depth" \
        \( -name Library -o -name node_modules -o -name .cache -o -name .local -o -name .Trash \
           -o -name .npm -o -name .nuget -o -name .dotnet -o -name obj -o -name bin -o -name .venv \) -prune -o \
        -type f -name '.git' -print0 2>/dev/null)}")

    local -a wts                # worktree working dirs
    local -A wt_gitcommon       # worktree -> the git dir that owns its registration (prune target)
    local gitfile line gd
    for gitfile in "${candidates[@]}"; do
        [[ -n "$gitfile" ]] || continue
        # `read` is a builtin: reading the one line we need costs no fork, unlike a grep per file.
        read -r line < "$gitfile" 2>/dev/null || continue
        [[ "$line" == 'gitdir: '* ]] || continue
        gd="${line#gitdir: }"
        [[ "$gd" == /* ]] || gd="${gitfile:h}/$gd"   # worktrees get an absolute path; submodules do not
        gd="${gd:A}"
        [[ "${gd:h:t}" == worktrees ]] || continue   # see note 1 — rejects submodules-in-worktrees
        wts+=("${gitfile:h}")
        wt_gitcommon[${gitfile:h}]="${gd:h:h}"
    done

    if (( ! ${#wts} )); then
        print -r -- "No git worktrees found under ${(j:, :)paths}"
        return 0
    fi

    # One du process for every worktree at once, instead of the two per worktree (`du -sk` then
    # `du -sh`) it used to take. Sizes are kept in KB so the display can format them fork-free.
    local -A wt_kb
    local l
    for l in "${(@f)$(command du -sk "${wts[@]}" 2>/dev/null)}"; do
        [[ -n "$l" ]] || continue
        wt_kb[${l#*$'\t'}]=${l%%$'\t'*}
    done

    # Insurance for the overlap assumption: if a worktree ever sits inside another, its bytes are
    # already in its parent's total, so only outermost worktrees contribute to the sum.
    local -a top
    local w other nested
    for w in "${wts[@]}"; do
        nested=false
        for other in "${wts[@]}"; do
            [[ "$w" != "$other" && "$w" == "$other"/* ]] && { nested=true; break; }
        done
        $nested || top+=("$w")
    done
    local -i total_kb=0
    for w in "${top[@]}"; do (( total_kb += ${wt_kb[$w]:-0} )); done

    # Guardrail: never silently delete uncommitted or unpushed work. Run in parallel because a
    # serial status+rev-list over dozens of large checkouts is slow enough to be annoying.
    local -A wt_dirty wt_ahead
    if $check; then
        # NOT named `path`: that is a special zsh parameter tied to PATH, and `local path` blanks
        # PATH for the rest of the function — which silently breaks every command below it.
        local out wt_path rest
        out=$(print -rN -- "${wts[@]}" | xargs -0 -P 8 -n 1 sh -c '
            wt=$1
            s=$(git --no-optional-locks -C "$wt" status --porcelain 2>/dev/null)
            d=0; [ -n "$s" ] && d=1        # also catches dirty submodule content, as a modified entry
            # Commits no remote-tracking ref has. Beats @{upstream} because a brand-new branch has
            # no upstream at all, which is exactly the case with the most to lose.
            a=$(git -C "$wt" rev-list --count HEAD --not --remotes 2>/dev/null) || a=0
            printf "%s\t%s\t%s\n" "$wt" "$d" "${a:-0}"
        ' _ 2>/dev/null)
        for l in "${(@f)out}"; do
            [[ -n "$l" ]] || continue
            wt_path="${l%%$'\t'*}"; rest="${l#*$'\t'}"
            wt_dirty[$wt_path]="${rest%%$'\t'*}"
            wt_ahead[$wt_path]="${rest##*$'\t'}"
        done
    fi

    local -aU containers repos
    for w in "${wts[@]}"; do containers+=("${w:h}"); done
    containers=("${(@o)containers}")
    repos=("${(@v)wt_gitcommon}")

    local -i namew=0
    for w in "${wts[@]}"; do (( ${#${w:t}} > namew )) && namew=${#${w:t}}; done
    (( namew > 52 )) && namew=52

    printf 'Found %d worktree(s) in %d repo(s):\n' ${#wts} ${#repos}
    local c mark
    for c in "${containers[@]}"; do
        printf '\n  \033[1m%s\033[0m\n' "${c/#$HOME/~}"
        for w in "${(@o)wts}"; do
            [[ "${w:h}" == "$c" ]] || continue
            mark=""
            (( ${wt_dirty[$w]:-0} )) && mark+=$'  \033[0;33m! dirty\033[0m'
            (( ${wt_ahead[$w]:-0} )) && mark+=$'  \033[0;33m↑'"${wt_ahead[$w]}"$' unpushed\033[0m'
            printf '    %-*s  \033[0;90m%6s\033[0m%s\n' \
                "$namew" "${w:t}" "$(_gwt_size ${wt_kb[$w]:-0})" "$mark"
        done
    done

    local -i ndirty=0 nahead=0
    for w in "${wts[@]}"; do
        (( ${wt_dirty[$w]:-0} )) && (( ndirty++ ))
        (( ${wt_ahead[$w]:-0} )) && (( nahead++ ))
    done
    local risk=""
    (( ndirty )) && risk="${ndirty} dirty"
    if (( nahead )); then
        [[ -n "$risk" ]] && risk+=", "
        risk+="${nahead} with unpushed commits"
    fi
    if [[ -n "$risk" ]]; then
        printf '\n  Total: %s  \033[0;33m— %s\033[0m\n\n' "$(_gwt_size $total_kb)" "$risk"
    else
        printf '\n  Total: %s\n\n' "$(_gwt_size $total_kb)"
    fi

    local gdir
    local -a plines
    local -i np
    if $dry_run; then
        # Surface stale registrations too: they are the part that accumulates unnoticed.
        for gdir in "${repos[@]}"; do
            # `worktree prune -v` reports on STDERR, not stdout — hence 2>&1, and hence the
            # Removing* filter so a real error is not miscounted as a pruned registration.
            plines=("${(@f)$(git --git-dir="$gdir" worktree prune --dry-run -v 2>&1)}")
            np=0; for l in "${plines[@]}"; do [[ "$l" == Removing* ]] && (( np++ )); done
            (( np )) && printf '  \033[0;90mwould prune %d stale registration(s) in %s\033[0m\n' \
                $np "${${gdir:h}/#$HOME/~}"
        done
        printf '  \033[0;90m(dry run — nothing removed)\033[0m\n'
        return 0
    fi

    if ! $assume_yes; then
        if [[ ! -t 0 ]]; then
            print -ru2 -- "git-worktrees-remove: no terminal to confirm on; pass --yes to proceed"
            return 1
        fi
        read -q "REPLY?Remove all ${#wts}? [y/N] " || { print; return 1; }
        print
    fi

    # Reduce the doomed set to disjoint removal roots first, rather than deciding per container
    # while deleting. A container collapses into one rm when every child of it is doomed — but
    # only if the container is not itself inside a doomed worktree, because that outer worktree
    # already takes it along. Skipping that test double-deletes: the rm succeeds, then the same
    # path turns up again as "already gone" and the tally silently under-counts.
    local -a roots=() in_c children
    local covered
    for c in "${(@O)containers}"; do
        covered=false
        for w in "${top[@]}"; do
            [[ "$c" == "$w" || "$c" == "$w"/* ]] && { covered=true; break; }
        done
        $covered && continue
        in_c=(); for w in "${wts[@]}"; do [[ "${w:h}" == "$c" ]] && in_c+=("$w"); done
        children=("$c"/*(/DN))          # (N) — an empty container must not abort the line on nomatch
        if (( ${#children} == ${#in_c} )); then
            roots+=("$c")
        else
            roots+=("${in_c[@]}")
        fi
    done

    local -i removed=0 failed=0
    local t
    for t in "${roots[@]}"; do
        # Credit every doomed worktree that lives at or under this root, so one rm of a container
        # holding three worktrees reports three.
        local -i n=0
        for w in "${wts[@]}"; do [[ "$w" == "$t" || "$w" == "$t"/* ]] && (( n++ )); done
        if [[ ! -e "$t" ]]; then
            printf '\033[0;90m  – %s (already gone)\033[0m\n' "${t/#$HOME/~}"
        elif rm -rf -- "$t" 2>/dev/null && [[ ! -e "$t" ]]; then
            (( removed += n ))          # confirm it is really gone: rm -rf exits 0 on a missing path
            if (( ${wts[(Ie)$t]} )); then
                if (( n > 1 )); then
                    printf '\033[1;32m  ✓ Removed %s \033[0;90m(with %d nested worktree(s))\033[0m\n' \
                        "${t/#$HOME/~}" $(( n - 1 ))
                else
                    printf '\033[1;32m  ✓ Removed %s\033[0m\n' "${t/#$HOME/~}"
                fi
            else
                printf '\033[1;32m  ✓ Removed %s \033[0;90m(%d worktree(s), entire container)\033[0m\n' \
                    "${t/#$HOME/~}" $n
            fi
        else
            (( failed++ ))
            printf '\033[0;31m  ✗ Failed to remove %s\033[0m\n' "${t/#$HOME/~}"
        fi
    done

    local -i total_pruned=0
    for gdir in "${repos[@]}"; do
        plines=("${(@f)$(git --git-dir="$gdir" worktree prune -v 2>&1)}")   # -v reports on stderr
        np=0; for l in "${plines[@]}"; do [[ "$l" == Removing* ]] && (( np++ )); done
        (( total_pruned += np ))
    done
    (( total_pruned )) && printf '\033[0;90m  pruned %d stale registration(s) across %d repo(s)\033[0m\n' \
        $total_pruned ${#repos}
    printf '\033[1;32m  %d worktree(s) removed\033[0m' $removed
    (( failed )) && printf '\033[0;31m, %d failed\033[0m' $failed
    print
    (( failed )) && return 1
    return 0
}
