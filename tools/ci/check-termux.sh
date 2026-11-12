#!/usr/bin/env bash
# Usage: bash tools/ci/check-termux.sh HOME [check ...] — checks a HOME that chezmoi rendered on Termux, one ok: or FAIL: line per check. plugins_once also runs on other systems
set -uo pipefail

home=$(cd "$1" && pwd)
shift
[ $# -gt 0 ] || set -- env_values aliases update_order clipboard_timeout clean_steps shortcuts_call_wrapper ua_without_zsh plugins_once \
    agent_rules gitconfig_gitlab codex_no_sandbox_on_android plugins_script_ci script_shebangs trust_homedir home_claude_md \
    packages_script default_shell font_script args_survive glibc_args_survive no_nested_proot \
    dotnet_wrapper_first old_dotnet_wrapper
repo=$(cd "$(dirname "$0")/../.." && pwd)
prefix=${PREFIX:-/data/data/com.termux/files/usr}
sh_path=$(command -v sh)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
failed=0
fakes=
render_config=$scratch/render.toml
printf '[data]\n    name = "CI"\n' > "$render_config"

ok() { echo "ok: $1"; }
fail() { echo "FAIL: $1"; failed=1; }

new_fakes() {
    fakes=$(mktemp -d "$scratch/fakes.XXXXXX")
}
fake() {
    printf '#!%s\n%s\n' "$sh_path" "$2" > "$fakes/$1"
    chmod +x "$fakes/$1"
}
copy_home() {
    local copy
    copy=$(mktemp -d "$scratch/home.XXXXXX")
    cp -R "$home/." "$copy"
    echo "$copy"
}

# Runs a command in an interactive shell on a HOME, the way a new Termux session starts; prints only what the command prints
termux_shell() {
    local shell=$1 h=$2
    shift 2
    (cd "$h" && env -i HOME="$h" PREFIX="$prefix" TERM=xterm-256color PATH="$fakes:$prefix/bin" \
        "$prefix/bin/$shell" -ic "echo __begin__; $*; echo __end__" </dev/null 2>/dev/null) | sed -n '/^__begin__$/,/^__end__$/p' | sed '1d;$d'
}

update_all() {
    local h=$1
    shift
    (cd "$h" && env -i HOME="$h" PREFIX="$prefix" TERM=dumb PATH="$fakes:$prefix/bin" \
        "$prefix/bin/zsh" "$h/.local/bin/update-all" "$@" </dev/null 2>&1) | sed 's/\x1b\[[0-9;]*m//g'
}

titles() {
    sed -n 's/^═* \(.*[^ ]\) ═*$/\1/p'
}

# Applies the repo to HOME the way the checked render was made, plus any extra environment, such as a fake glab on PATH
apply_into() {
    local h=$1
    shift
    env CI=true "$@" chezmoi --config "$render_config" --source "$repo" --destination "$h" --persistent-state "$h.boltdb" \
        apply --exclude externals,scripts --no-tty --force >/dev/null 2>&1
}

# Renders a .chezmoiscripts template the way a real apply outside CI does
render_script() {
    env -u CI chezmoi --config "$render_config" --source "$repo" execute-template < "$repo/.chezmoiscripts/$1" 2>/dev/null
}

check_env_values() {
    local shell out expected
    expected="TMPDIR=$prefix/tmp
DOTNET_ROOT=$home/.dotnet
DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
DOTNET_GCHeapHardLimit=1C0000000
DOTNET_gcServer=0
DOTNET_CLI_TELEMETRY_OPTOUT=1"
    new_fakes
    for shell in bash zsh; do
        out=$(termux_shell "$shell" "$home" 'for v in TMPDIR DOTNET_ROOT DOTNET_SYSTEM_GLOBALIZATION_INVARIANT DOTNET_GCHeapHardLimit DOTNET_gcServer DOTNET_CLI_TELEMETRY_OPTOUT; do eval "echo \"$v=\${$v:-}\""; done; echo "$PATH"')
        if [ "$(printf '%s\n' "$out" | sed '$d')" != "$expected" ]; then
            fail "env_values: $shell has other values:"
            printf '%s\n' "$out" | sed '$d' | sed 's/^/  /'
            continue
        fi
        if ! path_ok "$(printf '%s\n' "$out" | tail -n 1)"; then
            fail "env_values: $shell PATH lacks ~/scripts, ~/.local/bin or ~/.dotnet, or has ~/.dotnet before \$PREFIX/bin: $(printf '%s\n' "$out" | tail -n 1)"
            continue
        fi
        ok "env_values: $shell has the Termux values and PATH"
    done
}
path_ok() {
    local IFS=: dir i=0 bin_at='' dotnet_at='' scripts='' local_bin=''
    for dir in $1; do
        i=$((i + 1))
        case $dir in
            "$prefix/bin") [ -n "$bin_at" ] || bin_at=$i ;;
            "$home/.dotnet") [ -n "$dotnet_at" ] || dotnet_at=$i ;;
            "$home/scripts") scripts=1 ;;
            "$home/.local/bin") local_bin=1 ;;
        esac
    done
    [ -n "$scripts" ] && [ -n "$local_bin" ] && [ -n "$dotnet_at" ] && [ -n "$bin_at" ] && [ "$bin_at" -lt "$dotnet_at" ]
}

check_aliases() {
    local shell missing
    new_fakes
    fake termux-clipboard-set 'cat >/dev/null'
    fake termux-clipboard-get 'echo x'
    for shell in bash zsh; do
        missing=$(termux_shell "$shell" "$home" 'for n in ll ua ca cco ccr pbcopy pbpaste; do type "$n" >/dev/null 2>&1 || echo "$n"; done' | tr '\n' ' ')
        if [ -n "$missing" ]; then
            fail "aliases: $shell lacks $missing"
        else
            ok "aliases: $shell defines ll, ua, ca, cco, ccr, pbcopy and pbpaste"
        fi
    done
}

check_update_order() {
    local h out titles_seen expected
    h=$(copy_home)
    mkdir -p "$h/.local/share/claude" "$h/.codex/packages/standalone/current" "$scratch/dotfiles-src/.git"
    touch "$h/.local/share/claude/claude-native"
    new_fakes
    fake claude 'exit 0'
    fake dotnet 'exit 0'
    fake agy 'exit 0'
    fake chezmoi "case \$1 in source-path) echo '$scratch/dotfiles-src' ;; esac"
    out=$(update_all "$h" --dry-run)
    titles_seen=$(printf '%s\n' "$out" | titles | grep -xE 'Termux Packages|Claude Code|Claude Code Plugins|Codex CLI|\.NET SDK|\.NET Global Tools|Dotfiles' | tr '\n' '|')
    expected='Termux Packages|Claude Code|Claude Code Plugins|Codex CLI|.NET SDK|.NET Global Tools|Dotfiles|'
    if [ "$titles_seen" != "$expected" ]; then
        fail "update_order: the dry run lists $titles_seen"
    elif [ "$(printf '%s\n' "$out" | titles | head -n 1)" != 'Termux Packages' ]; then
        fail "update_order: Termux Packages is not the first step"
    elif printf '%s\n' "$out" | grep -q 'agy update'; then
        fail "update_order: the dry run runs agy update"
    elif printf '%s\n' "$out" | titles | grep -qx APT; then
        fail "update_order: the dry run lists APT"
    else
        ok "update_order: termux-pkg, claude-code, claude, codex, dotnet-sdk, dotnet and dotfiles run in order, with no agy update and no APT"
    fi
    if ! command -v termux-chroot >/dev/null 2>&1; then
        fail "update_order: termux-chroot is missing, so APT inside the chroot is untested (pkg install proot)"
    elif termux-chroot "cd $h && HOME=$h PREFIX=$prefix TERM=dumb PATH=$fakes:/usr/bin:$prefix/bin zsh $h/.local/bin/update-all --dry-run </dev/null" 2>/dev/null \
        | sed 's/\x1b\[[0-9;]*m//g' | titles | grep -qx APT; then
        fail "update_order: inside termux-chroot, where /etc/apt is Termux's, the dry run lists APT"
    else
        ok "update_order: inside termux-chroot the dry run does not list APT"
    fi
}

check_clipboard_timeout() {
    local shell start out
    new_fakes
    fake termux-clipboard-set 'exec sleep 60'
    for shell in bash zsh; do
        start=$SECONDS
        out=$(termux_shell "$shell" "$home" 'echo x | pbcopy 2>&1; echo "rc=$?"')
        if [ $((SECONDS - start)) -gt 5 ]; then
            fail "clipboard_timeout: $shell pbcopy took $((SECONDS - start)) s"
        elif ! printf '%s\n' "$out" | grep -qx 'pbcopy needs the Termux:API app'; then
            fail "clipboard_timeout: $shell pbcopy printed: $out"
        elif ! printf '%s\n' "$out" | grep -qx 'rc=1'; then
            fail "clipboard_timeout: $shell pbcopy did not return 1: $out"
        else
            ok "clipboard_timeout: $shell pbcopy gives up within 5 s and names the Termux:API app"
        fi
    done
}

check_clean_steps() {
    local h out missing='' want
    h=$(copy_home)
    new_fakes
    fake dotnet 'exit 0'
    fake npm 'exit 0'
    fake pip 'exit 0'
    fake go 'exit 0'
    out=$(update_all "$h" --clean --dry-run)
    for want in 'pkg clean' 'apt autoremove -y' 'dotnet nuget locals all --clear' 'npm cache clean --force' '.npm/_npx' 'pip cache purge' 'go clean -cache -modcache' "$prefix/tmp" '! -name work-profile'; do
        printf '%s\n' "$out" | grep -qF -- "$want" || missing="$missing '$want'"
    done
    if [ -n "$missing" ]; then
        fail "clean_steps: the clean dry run lacks$missing"
    else
        ok "clean_steps: the clean dry run names pkg clean, the caches, \$PREFIX/tmp and the work-profile exception"
    fi
}

check_shortcuts_call_wrapper() {
    local f bad='' count=0
    for f in "$home"/.shortcuts/*; do
        [ -f "$f" ] || continue
        count=$((count + 1))
        sed 1d "$f" | grep -v '^[[:space:]]*$' | grep -qv '^exec "\$HOME/\.local/bin/claude"' && bad="$bad ${f##*/}"
        grep -q '^exec "\$HOME/\.local/bin/claude"' "$f" || bad="$bad ${f##*/}"
    done
    if [ "$count" -eq 0 ]; then
        fail "shortcuts_call_wrapper: ~/.shortcuts has no files"
    elif [ -n "$bad" ]; then
        fail "shortcuts_call_wrapper: these shortcuts do not only exec ~/.local/bin/claude:$bad"
    else
        ok "shortcuts_call_wrapper: all $count shortcuts exec ~/.local/bin/claude"
    fi
}

check_ua_without_zsh() {
    local nozsh out rc f
    nozsh=$(mktemp -d "$scratch/nozsh.XXXXXX")
    for f in "$prefix"/bin/*; do
        [ "${f##*/}" = zsh ] || ln -s "$f" "$nozsh/"
    done
    out=$(cd "$home" && env -i HOME="$home" PREFIX="$prefix" TERM=xterm-256color PATH="$nozsh" "$prefix/bin/bash" -ic ua </dev/null 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then
        fail "ua_without_zsh: ua exited 0 without zsh"
    elif ! printf '%s\n' "$out" | grep -qx 'update-all needs zsh: pkg install zsh'; then
        fail "ua_without_zsh: ua printed: $(printf '%s\n' "$out" | tail -n 3)"
    else
        ok "ua_without_zsh: ua names the zsh package and fails"
    fi
}

check_plugins_once() {
    local h log
    h=$(copy_home)
    log=$scratch/plugin-updates.log
    : > "$log"
    new_fakes
    fake claude "case \"\$1 \$2\" in
'plugin list') for scope in user project local; do printf '  a@m\n  b@m\n'; done ;;
'plugin update') echo \"\$3\" >> '$log' ;;
esac"
    fake sudo 'exit 1'
    (cd "$h" && env -i HOME="$h" TERM=dumb PATH="$fakes:$PATH" zsh "$h/.local/bin/update-all" claude </dev/null >/dev/null 2>&1)
    if [ "$(sort "$log" | tr '\n' ' ')" = 'a@m b@m ' ]; then
        ok "plugins_once: update-all claude updates each plugin once"
    else
        fail "plugins_once: update-all claude ran: $(tr '\n' ' ' < "$log")"
    fi
}

check_agent_rules() {
    local f missing=''
    for f in .claude/CLAUDE.md .codex/AGENTS.md .gemini/GEMINI.md; do
        if ! grep -qF 'glibc-runner' "$home/$f" 2>/dev/null || ! grep -qF '$TMPDIR' "$home/$f"; then
            missing="$missing ~/$f"
        fi
    done
    if [ -n "$missing" ]; then
        fail "agent_rules: these lack the Termux rules:$missing"
    else
        ok "agent_rules: Claude Code, Codex and agy get the Termux rules"
    fi
}

check_gitconfig_gitlab() {
    local h helpers rewrite
    h=$(mktemp -d "$scratch/git.XXXXXX")
    new_fakes
    fake glab 'exit 0'
    if ! apply_into "$h" PATH="$fakes:$PATH"; then
        fail "gitconfig_gitlab: chezmoi apply failed"
        return
    fi
    helpers=$(git config -f "$h/.gitconfig" --get-all credential.https://gitlab.com.helper | tr '\n' '|')
    rewrite=$(git config -f "$h/.gitconfig" --get url.https://gitlab.com/.insteadOf)
    if [ "$helpers" = '|!glab auth git-credential|' ] && [ "$rewrite" = 'git@gitlab.com:' ]; then
        ok "gitconfig_gitlab: with glab, GitLab uses the glab login over HTTPS"
    else
        fail "gitconfig_gitlab: gitlab.com helpers are '$helpers' and insteadOf is '$rewrite'"
    fi
}

check_codex_no_sandbox_on_android() {
    local h want missing=''
    h=$(mktemp -d "$scratch/codex.XXXXXX")
    if ! apply_into "$h" || ! apply_into "$h"; then
        fail "codex_no_sandbox_on_android: chezmoi apply failed"
        return
    fi
    for want in 'sandbox_mode = "danger-full-access"' 'approval_policy = "on-request"' 'approvals_reviewer = "auto_review"'; do
        grep -qxF "$want" "$h/.codex/config.toml" || missing="$missing '$want'"
    done
    if [ -n "$missing" ]; then
        fail "codex_no_sandbox_on_android: after two applies, ~/.codex/config.toml lacks$missing"
    else
        ok "codex_no_sandbox_on_android: Codex runs with no sandbox and the auto reviewer, and a second apply keeps it"
    fi
}

check_plugins_script_ci() {
    local out
    out=$(CI=true chezmoi --config "$render_config" --source "$repo" execute-template \
        < "$repo/.chezmoiscripts/run_onchange_after_install-agent-plugins.sh.tmpl" 2>&1)
    if [ -z "$(printf '%s' "$out" | tr -d '[:space:]')" ]; then
        ok "plugins_script_ci: the agent plugins script renders empty in CI"
    else
        fail "plugins_script_ci: in CI the agent plugins script renders: $(printf '%s\n' "$out" | head -n 2 | tr '\n' ' ')"
    fi
}

# chezmoi starts scripts without termux-exec, and Android's /bin is /system/bin, which has sh but no bash
check_script_shebangs() {
    local f name out first bad=
    for f in "$repo"/.chezmoiscripts/*.sh.tmpl; do
        name=$(basename "$f")
        out=$(render_script "$name")
        [ -n "$(printf '%s' "$out" | tr -d '[:space:]')" ] || continue
        first=$(printf '%s\n' "$out" | head -n 1)
        [ "$first" = "#!/bin/sh" ] || bad="$bad $name ($first)"
    done
    if [ -z "$bad" ]; then
        ok "script_shebangs: every Termux setup script starts with #!/bin/sh"
    else
        fail "script_shebangs: the phone cannot start:$bad"
    fi
}

check_trust_homedir() {
    local h script
    h=$(mktemp -d "$scratch/trust.XXXXXX")
    script=$scratch/trust.sh
    render_script run_onchange_after_claude-trust-homedir.sh.tmpl > "$script"
    printf '{"projects": {"/x": {"hasTrustDialogAccepted": false}}}\n' > "$h/.claude.json"
    (cd "$h" && HOME="$h" sh "$script" >/dev/null 2>&1)
    if jq -e '.projects["/x"].hasTrustDialogAccepted == true' "$h/.claude.json" >/dev/null 2>&1; then
        ok "trust_homedir: the trust script accepts the trust dialog in ~/.claude.json"
    else
        fail "trust_homedir: ~/.claude.json still has: $(tr -d '\n' < "$h/.claude.json")"
    fi
}

check_home_claude_md() {
    local h script out old_ok=1
    h=$(mktemp -d "$scratch/claudemd.XXXXXX")
    script=$scratch/remove-claude-md.sh
    render_script run_once_after_remove-termux-home-claude-md.sh.tmpl > "$script"
    echo 'my own notes' > "$h/CLAUDE.md"
    out=$(cd "$h" && HOME="$h" sh "$script" 2>&1)
    # shellcheck disable=SC2088 # the script prints the path with a literal ~
    if [ ! -f "$h/CLAUDE.md" ] || [ "$out" != '~/CLAUDE.md differs from the old managed copy, so it was kept' ]; then
        fail "home_claude_md: a changed ~/CLAUDE.md was not kept with the message: $out"
        return
    fi
    if git -C "$repo" cat-file -e 203acb8:CLAUDE.md 2>/dev/null; then
        git -C "$repo" show 203acb8:CLAUDE.md > "$h/CLAUDE.md"
        (cd "$h" && HOME="$h" sh "$script" >/dev/null 2>&1)
        [ ! -e "$h/CLAUDE.md" ] || old_ok=0
    fi
    if [ "$old_ok" = 1 ]; then
        ok "home_claude_md: a changed ~/CLAUDE.md stays, and the old managed copy goes when git history has it"
    else
        fail "home_claude_md: the old managed ~/CLAUDE.md was not removed"
    fi
}

check_packages_script() {
    local script log first rest
    script=$scratch/packages.sh
    log=$scratch/pkg.log
    : > "$log"
    render_script run_onchange_before_termux-packages.sh.tmpl > "$script"
    new_fakes
    fake dpkg 'case $2 in zsh|git|chezmoi) exit 0 ;; *) exit 1 ;; esac'
    fake pkg "echo \"\$*\" >> '$log'"
    (PATH="$fakes:$PATH" sh "$script" >/dev/null 2>&1)
    first=$(sed -n 1p "$log")
    rest=" $(sed -n 2p "$log") "
    if grep -qE 'upgrade|uninstall|remove' "$log"; then
        fail "packages_script: pkg ran: $(tr '\n' ' ' < "$log")"
    elif [ "$(grep -c . "$log")" != 2 ] || [ "$first" != 'install -y glibc-repo' ]; then
        fail "packages_script: expected glibc-repo first, then one install, but pkg ran: $(tr '\n' ' ' < "$log")"
    else
        case $rest in
            " install -y "*" glibc-runner "*)
                case $rest in
                    *" zsh "*|*" git "*|*" chezmoi "*) fail "packages_script: it reinstalls a package that dpkg reports: $rest" ;;
                    *) ok "packages_script: pkg installs glibc-repo first, then only the missing packages" ;;
                esac ;;
            *) fail "packages_script: the second pkg call lacks glibc-runner: $rest" ;;
        esac
    fi
}

check_default_shell() {
    if [ -L "$home/.termux/shell" ] && [ "$(readlink "$home/.termux/shell")" = "$prefix/bin/zsh" ]; then
        ok "default_shell: ~/.termux/shell links to zsh"
    else
        fail "default_shell: ~/.termux/shell is not a link to $prefix/bin/zsh"
    fi
}

check_font_script() {
    local h script calls rc
    h=$(mktemp -d "$scratch/font.XXXXXX")
    script=$scratch/font.sh
    calls=$scratch/font-calls.log
    : > "$calls"
    render_script run_onchange_after_install-font.sh.tmpl > "$script"
    mkdir -p "$scratch/fontsrc"
    echo fontdata > "$scratch/fontsrc/JetBrainsMonoNerdFontMono-Regular.ttf"
    tar -cJf "$scratch/font.tar.xz" -C "$scratch/fontsrc" JetBrainsMonoNerdFontMono-Regular.ttf
    new_fakes
    fake curl "echo curl >> '$calls'; cat '$scratch/font.tar.xz'"
    fake termux-reload-settings "echo reload >> '$calls'"
    (HOME="$h" PATH="$fakes:$PATH" sh "$script" >/dev/null 2>&1)
    rc=$?
    if [ "$rc" != 0 ] || [ "$(cat "$h/.termux/font.ttf" 2>/dev/null)" != fontdata ] || [ "$(tr '\n' ' ' < "$calls")" != 'curl reload ' ]; then
        fail "font_script: first run exited $rc, called: $(tr '\n' ' ' < "$calls")"
        return
    fi
    (HOME="$h" PATH="$fakes:$PATH" sh "$script" >/dev/null 2>&1)
    rc=$?
    if [ "$rc" != 0 ] || [ "$(tr '\n' ' ' < "$calls")" != 'curl reload ' ]; then
        fail "font_script: with the font in place, it exited $rc and called: $(tr '\n' ' ' < "$calls")"
    else
        ok "font_script: the font script installs ~/.termux/font.ttf once and reloads Termux"
    fi
}

tricky_args() {
    "$@" 'a b' "it's" '$HOME' '*' ''
}
tricky_lines() {
    printf '%s\n' 'a b' "it's" '$HOME' '*' ''
    echo .
}

check_args_survive() {
    local exec=$home/.local/bin/termux-chroot-exec out inner plain
    if [ ! -x "$exec" ]; then
        fail "args_survive: ~/.local/bin/termux-chroot-exec is missing"
        return
    fi
    out=$(tricky_args "$exec" printf '%s\n' 2>/dev/null; echo .)
    printf '%s\n' "$(declare -f tricky_args)" "tricky_args '$exec' printf '%s\n'" > "$scratch/in-chroot.sh"
    inner=$(termux-chroot "bash $scratch/in-chroot.sh" 2>/dev/null; echo .)
    plain=$(termux-chroot printf '%s\n' "a b" 2>/dev/null)
    if [ "$out" != "$(tricky_lines)" ]; then
        fail "args_survive: outside the chroot it printed: $(printf '%s' "$out" | tr '\n' '|')"
    elif [ "$inner" != "$(tricky_lines)" ]; then
        fail "args_survive: inside the chroot it printed: $(printf '%s' "$inner" | tr '\n' '|')"
    else
        ok "args_survive: termux-chroot-exec passes spaces, quotes, \$HOME, * and an empty argument unchanged, outside and inside the chroot (plain termux-chroot prints '$plain')"
    fi
}

check_glibc_args_survive() {
    local h out
    h=$(copy_home)
    mkdir -p "$h/.local/share/claude"
    printf '#!%s\nprintf "%%s\\n" "$@"\n' "$sh_path" > "$h/.local/share/claude/claude-native"
    chmod +x "$h/.local/share/claude/claude-native"
    out=$(cd "$h" && HOME="$h" "$h/.local/bin/claude" -p "fix it (now), it's \$HOME" 2>/dev/null)
    if [ "$out" = "$(printf '%s\n' -p "fix it (now), it's \$HOME")" ]; then
        ok "glibc_args_survive: claude -p gets a prompt with spaces, ( and ' as one argument"
    else
        fail "glibc_args_survive: the stand-in Claude got: $(printf '%s' "$out" | tr '\n' '|')"
    fi
}

check_no_nested_proot() {
    local h log out wrapper bad=''
    h=$(copy_home)
    log=$scratch/nested-proot.log
    : > "$log"
    new_fakes
    fake termux-chroot "echo termux-chroot >> '$log'; exit 1"
    mkdir -p "$h/.local/share/claude" "$h/.codex/packages/standalone/current/bin" "$h/.dotnet"
    for wrapper in "$h/.local/share/claude/claude-native" "$h/.codex/packages/standalone/current/bin/codex" "$h/.dotnet/dotnet"; do
        printf '#!%s\nprintf "%%s\\n" "$@"\n' "$sh_path" > "$wrapper"
        chmod +x "$wrapper"
    done
    for wrapper in "$h/.local/bin/claude" "$h/.local/bin/codex" "$h/.local/bin/dotnet"; do
        printf '%s\n' "export HOME='$h' PATH='$fakes:/usr/bin'" "'$wrapper' 'x y'" > "$scratch/nested.sh"
        out=$(termux-chroot "bash $scratch/nested.sh" 2>/dev/null)
        printf '%s\n' "$out" | grep -qx 'x y' || bad="$bad ${wrapper##*/}(no 'x y')"
    done
    if [ -s "$log" ]; then
        fail "no_nested_proot: inside the chroot, the wrappers called termux-chroot $(grep -c . "$log") times"
    elif [ -n "$bad" ]; then
        fail "no_nested_proot: these wrappers did not reach their stand-in with the argument intact:$bad"
    else
        ok "no_nested_proot: inside the chroot, claude, codex and dotnet start no second proot"
    fi
}

check_dotnet_wrapper_first() {
    local shell found
    new_fakes
    fake dotnet 'exit 0'
    for shell in bash zsh; do
        found=$(termux_shell "$shell" "$home" 'command -v dotnet')
        if [ "$found" = "$home/.local/bin/dotnet" ]; then
            ok "dotnet_wrapper_first: $shell finds ~/.local/bin/dotnet first"
        else
            fail "dotnet_wrapper_first: $shell finds dotnet at '$found'"
        fi
    done
}

check_old_dotnet_wrapper() {
    local fake_prefix script out
    fake_prefix=$(mktemp -d "$scratch/prefix.XXXXXX")
    mkdir -p "$fake_prefix/bin"
    script=$scratch/remove-old-dotnet.sh
    render_script run_once_after_remove-old-dotnet-wrapper.sh.tmpl > "$script"
    printf '%s\n' '#!/data/data/com.termux/files/usr/bin/bash' 'exec termux-chroot glibc-runner -n "$HOME/.dotnet/dotnet" "$@"' > "$fake_prefix/bin/dotnet"
    PREFIX=$fake_prefix sh "$script" >/dev/null 2>&1
    if [ -e "$fake_prefix/bin/dotnet" ]; then
        fail "old_dotnet_wrapper: the old wrapper that dotnet-setup.sh wrote is still in \$PREFIX/bin"
        return
    fi
    echo 'something else' > "$fake_prefix/bin/dotnet"
    out=$(PREFIX=$fake_prefix sh "$script" 2>&1)
    if [ -e "$fake_prefix/bin/dotnet" ] && [ -n "$out" ]; then
        ok "old_dotnet_wrapper: the script removes only the old wrapper, and names any other \$PREFIX/bin/dotnet"
    else
        fail "old_dotnet_wrapper: another \$PREFIX/bin/dotnet was removed, or kept without a message"
    fi
}

for check in "$@"; do
    "check_$check"
done
exit "$failed"
