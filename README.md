# Dotfiles (macOS / Linux / Windows / WSL / MSYS / Termux)

Managed with [chezmoi](https://chezmoi.io). The `main` branch serves every system, including Termux on Android.

## Quick start

chezmoi can clone this public repo without a login. Log in with the GitHub CLI (`gh`) first anyway, because the applied `~/.gitconfig` asks `gh` for the GitHub credentials that a push needs.

1. Install chezmoi and `gh` with the command for your system (table below).
2. Log in to GitHub and let git use that login (first two commands below).
3. Clone and apply this repo (third command). If chezmoi went to `~/.local/bin`, run it as `~/.local/bin/chezmoi`.
4. When `chezmoi init` asks for a work dotfiles repo and for more layers, leave both empty on a machine without layers. See "Layers" below.

| System | Install chezmoi and gh |
|---|---|
| macOS | `brew install chezmoi gh` |
| Debian, Ubuntu, WSL | `sudo apt install gh`, then `sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin` |
| Fedora | `sudo dnf install chezmoi gh` |
| Arch | `sudo pacman -S chezmoi github-cli` |
| Windows (Git Bash) | `winget install twpayne.chezmoi GitHub.cli` |
| Termux (Android) | Use the bootstrap in "Termux" below. It installs both and applies this repo |

```bash
gh auth login
gh auth setup-git
chezmoi init --apply RonAmihai
```

`chezmoi apply` replaces the `~/.gitconfig` that `gh auth setup-git` wrote. The new one still asks `gh` for GitHub credentials, so later pulls work too.

On WSL, reuse the Windows checkout instead of cloning again. Run `chezmoi init --source /mnt/c/Users/<windows-user>/.local/share/chezmoi --apply`. The generated configuration remembers that shared source directory. WSL still gets its own Linux home and platform-specific rendered files.

### Termux

1. Install Termux and its add-on apps, Termux:API and Termux:Widget, from the same source. Android refuses an add-on app that another source signed.
2. Use the GitHub builds, and keep them current with Obtainium.
3. Never let another store's app uninstall Termux, for example to replace it with its own build. Uninstalling deletes all of Termux's data.
4. In Termux, run this bootstrap. It logs in to GitHub, then runs `scripts/executable_termux-setup.sh` from `main`.

```bash
pkg upgrade -y && pkg install -y git gh && { gh auth status &>/dev/null || gh auth login; } && { gh api 'repos/RonAmihai/dotfiles/contents/scripts/executable_termux-setup.sh?ref=main' --jq '.content' | base64 -d | bash; }
```

The setup applies this repo with no layers. chezmoi then installs the packages in `~/.config/termux/packages.txt`, the prompt font, and zsh as the Termux shell. At the end, the setup offers to install .NET, Claude Code, Codex and `agy`. Then close Termux fully and open it again.

## Set up a new workstation with an agent

An agent can follow these steps on a new machine. The user gives the agent the list of layers: a short name and a repo URL for each. Never write that list, or a URL from it, into a file in this repo, a commit or a log.

1. Ask the user for the layers. A machine can have none.
2. Install chezmoi and `gh` with the command for the system (table above). Then the user runs `gh auth login` and `gh auth setup-git`.
3. If a layer lives on another git host, the user also logs in to that host, for example with `glab auth login`. The agent never handles a password or a token.
4. Write the layers into the chezmoi configuration file, then apply this repo. If `~/.config/chezmoi/chezmoi.toml` already exists, stop and ask the user. Put all pairs in one string, with a space between two pairs. With no layers, use an empty string:

```bash
mkdir -p ~/.config/chezmoi
printf '[data]\n    work_dotfiles_repo = ""\n    dotfiles_layers = "%s"\n' '<name>=<repo URL> <name>=<repo URL>' > ~/.config/chezmoi/chezmoi.toml
chezmoi init --apply RonAmihai
```

5. After the first apply, a script clones each layer into `~/.local/share/chezmoi-<name>` and applies it. Run `chezmoi apply` once more, so that the templates here read the data that the layers added.
6. Read the README of each layer, and do the steps that it lists.
7. Open a new terminal, and make sure that the shell starts with no error. Then run `chezmoi-<name> status` for each layer, and make sure that it lists no file.

To change the layers later, edit `dotfiles_layers` in `~/.config/chezmoi/chezmoi.toml`, then run `chezmoi apply`. On Termux, the bootstrap in "Termux" does steps 2 and 4 without layers, so add them this way afterwards.

## Layers

This repo holds nothing about an employer and nothing private. Other dotfiles repos, called layers, add files on top of it. Each layer has its own chezmoi source (`~/.local/share/chezmoi-<name>`), its own state and its own `chezmoi-<name>` command, and its README lists what it adds. A work layer holds the files for an employer. A private layer holds personal files that stay out of this public repo.

1. On a new machine, `chezmoi init` asks for the work repo URL and for more layers as `name=URL` pairs. The work repo URL becomes the layer `work`.
2. After the first `chezmoi apply`, a script clones each layer and applies it with its own chezmoi.
3. Run `chezmoi apply` once more. The templates here then read the data that the layers added.

A layer can add to these places:

| Place | What it adds |
|---|---|
| `~/.config/git/work.gitconfig` | Git rules, for example a work email for work remotes. `~/.gitconfig` includes this file last |
| `~/.config/chezmoi/data.d/*.json` | Data for the templates here: `nono_extra_signin_origins`, `nono_extra_fs_allow`, `nono_extra_fs_read`, `cmux_workspace_groups`, `agent_mcp_servers` (MCP servers for Codex, `agy` and opencode), `agent_allowed_commands` (commands that Claude Code and `agy` run without a prompt) and `agent_retired_commands` (commands that chezmoi removes from their settings) |
| `~/.claude/settings.json` | Permissions, marketplaces, plugins and hooks. The template here adds its own entries and keeps every entry that it does not list |
| `~/.config/homebrew/<name>.Brewfile` | Packages. The Brewfile script installs every `*.Brewfile` in that folder |
| `~/.config/shell/tools/` | Tool files, which load with the tool files of this repo |
| `~/.ssh/config.d/` | SSH hosts, for example the work git host and its key. `~/.ssh/config` loads these files first |
| `~/.config/chezmoi/forbidden-terms.d/` | Employer terms, one extended regex per line. This repo's pre-push hook blocks a push whose files, added lines, commit messages or authors match one |
| `~/.config/agent-rules/` | Rules for coding agents: `shared/` for every agent, and `claude/`, `codex/` or `antigravity/` for one agent. See the agent rules row below |
| `~/.claude/skills/`, `~/.codex/skills/`, `~/.gemini/config/skills/` | Skills for Claude Code, Codex and `agy`. All three read the same skill format, so one source file can serve all three. opencode reads `~/.claude/skills/` too |
| `~/.config/shell/tools/` | One tool file per work tool: shell setup, aliases and `update-all` steps (see "Tool files" below) |
| `~/.config/homebrew/*.Brewfile` | Work packages. The script here installs them on the next `chezmoi apply` (see "Packages" below) |

A path that the work repo writes in a file, such as a git include, should be relative or use `${XDG_CONFIG_HOME:-$HOME/.config}`, not `~`. Then the same file also works in a temporary work profile.

### Work on a machine without the work layer

On a phone or a temporary machine, the work layer can live in a temporary profile instead, so no work file stays between sessions. `work` does this on macOS, Linux and Termux. A machine that has the work layer installed keeps it, and `work` refuses to start there.

1. `work` clones the work repo into the profile: `$PREFIX/tmp/work-profile` on Termux, and `$TMPDIR/work-profile-<uid>` elsewhere. Then it applies the work repo and this repo into the profile's own home folder.
2. The session shell sets one variable per tool, so each tool reads the profile: `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `GH_CONFIG_DIR`, `GLAB_CONFIG_DIR`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `GIT_CONFIG_GLOBAL` and the shell history. `DOTFILES_HOME` makes the shell load the work tool files from the profile. The .NET, NuGet, npm, Go and pip caches move into the profile too, so a work project's packages go with it. `agy` gets the profile as its `HOME`, because it has no config folder variable.
3. In the session, log in to each tool that you need. The GitHub login comes from your own one.
4. When you leave the shell with `exit`, `work` lists the folders in your home folder whose files changed during the session, so you can check that none holds work data. It skips `~/.dotnet`, `~/Library` and `~/storage`, which hold most of the files. Then it deletes the profile.

A tool that keeps a login outside its config folder, for example in the macOS Keychain, keeps it after the session. Check for such a login after a session on a machine that is not yours.

The work repo URL comes from the argument, `$WORK_DOTFILES_REPO`, or the `export WORK_DOTFILES_REPO=...` line in `~/.local.zsh`. Without one, `work` asks for it and saves it there. chezmoi does not manage `~/.local.zsh`, so the URL never reaches this repo.

`work --status` shows whether a profile is on disk. If the terminal closes during a session, the profile stays, and every new shell names it. Then `work --end` shows the changed folders and deletes the profile. `update-all` and `clean-all` refuse to run in a session, because they would change the real home. On Termux, `clean-all` keeps the profile of a running session.

### Start a work repo for a new employer

`tools/work-layer-skeleton/` is a starter work repo. CI applies it on top of this repo, so it stays in step with the places above.

1. Create an empty private repo on the employer's git host, in your own namespace.
2. Copy the starter repo and start git in the copy (first two commands below).
3. In `dot_config/git/`, replace `example-org` with the employer's organization and `you@example.com` with your work email.
4. Add a pattern for your own namespace on that host to `work.gitconfig.tmpl`, so that commits to the work repo get the work email.
5. Add the work files: shell functions, Claude Code rules, permissions, plugins and template data.
6. Apply the work layer, then apply this repo again, so that the templates here read the work data.
7. Add the remote before the first commit, so that the commit gets the work identity. Then push.
8. Set `work_dotfiles_repo` in `~/.config/chezmoi/chezmoi.toml` to the repo URL. On a new machine, `chezmoi init` asks for it.

```sh
cp -R ~/.local/share/chezmoi/tools/work-layer-skeleton ~/.local/share/chezmoi-work
git -C ~/.local/share/chezmoi-work init -b main
chezmoi --source ~/.local/share/chezmoi-work --config ~/.config/chezmoi-work/chezmoi.toml apply
chezmoi apply
git -C ~/.local/share/chezmoi-work remote add origin <work repo URL>
git -C ~/.local/share/chezmoi-work add -A
git -C ~/.local/share/chezmoi-work commit -m "Work dotfiles"
git -C ~/.local/share/chezmoi-work push -u origin main
```

After the first apply, use `chezmoi-work` for the work repo in the same way as `chezmoi`. The first apply also turns on a pre-push check in the work repo: zsh syntax, JSON and template rendering. Never put anything about the employer in this repo. Never put a secret in the work repo: read secrets at run time from a login or from a local file outside every repo.

Put the GPG key and the credential helpers of this machine in `~/.gitconfig.local`:

```ini
[user]
    signingkey = <GPG-KEY-ID>
[credential]
    helper = /usr/local/bin/git-credential-manager
```

## What's included

| Target | Source | Description |
|---|---|---|
| `~/.config/shell/tools/` | `dot_config/shell/tools/` | One file per tool, for zsh and bash: PATH, exports, setup, completion, aliases, `update-all` steps and the code behind the commands in `~/.local/bin`. See "Tool files" below |
| `~/.config/shell/env.sh` | `dot_config/shell/env.sh` | Shared by zsh and bash: locale, `~/.local/bin`, the tool file cache, the path and env phases, AI agent detection. POSIX syntax |
| `~/.config/shell/aliases.sh` | `dot_config/shell/aliases.sh` | Shared by zsh and bash: general aliases, clipboard, small helpers |
| `~/.zshenv` | `dot_zshenv` | Read by every zsh. Turns off aliases in scripts and loads `zshenv.d/` |
| `~/.zshrc` | `dot_zshrc` | ZSH entry point: `.personal.zsh`, then the tool files' setup phase, `~/.local.zsh`, and the aliases phase last |
| `~/.personal.zsh` | `dot_personal.zsh` | ZSH only: history, zinit plugins, completion, key bindings |
| `~/.config/zsh/zshenv.d/` | `dot_config/zsh/zshenv.d/` | ZSH only: code that must run before a terminal's own zsh integration (cmux, Debian) |
| `~/.local/share/zinit/zinit.git` | `.chezmoiexternal.toml` | The zinit plugin manager. If it is missing, `chezmoi apply` clones it |
| `~/.bashrc` | `dot_bashrc` | Bash entry point (bash 3.2 and later): the shared files, history, the tool files' setup phase, completion, `~/.local.bash`, and the aliases phase last |
| `~/.bash_profile` | `dot_bash_profile` | Login shells (macOS Terminal, Git Bash) read this file. It loads `~/.profile` and `~/.bashrc` |
| `~/.config/powershell/` | `dot_config/powershell/` | One PowerShell Core profile for Windows, macOS and Linux. It shares aliases and command names with zsh and bash. Windows-only update and window helpers load conditionally. A generated bridge supports relocated Documents folders and Windows PowerShell 5.1 |
| `~/.config/cmd/profile.cmd`, `autorun.cmd` | `dot_config/cmd/` | The safe alias subset for Cmd. A Windows-only script adds `autorun.cmd` to Cmd AutoRun, and it keeps an existing AutoRun command. `autorun.cmd` loads the profile only in an interactive Cmd, so a `cmd /c` from a build tool or a script starts without it |
| `~/.gitconfig` | `dot_gitconfig.tmpl` | Global git file with the personal email. Machine-local values (GPG key, credentials) go in `~/.gitconfig.local` |
| `~/.config/git/ignore` | `dot_config/git/ignore` | Global gitignore |
| `~/.claude/settings.json` | `dot_claude/modify_settings.json` | Chezmoi owns the permissions it lists, the status line, its marketplaces, the output style and the screen layout in this file. Claude Code owns the model, effort and plugins, and chezmoi writes them only on a new machine |
| `~/.config/agent-hooks/git-consent-reminder.sh` | `dot_config/agent-hooks/executable_git-consent-reminder.sh` | Claude Code, Codex, `agy` and opencode add a git consent reminder to every prompt, so that agents commit and push only on request. The hook entries go in `~/.claude/settings.json`, `~/.codex/hooks.json` and `~/.gemini/config/hooks.json`, and other hooks stay. opencode runs it from the plugin `~/.config/opencode/plugins/git-consent.ts`. On Windows, Codex, `agy` and opencode skip it |
| `~/.agents/skills/visual-plan/`, `~/.claude/skills/visual-plan/` | `dot_agents/skills/visual-plan/` | The visual-plan skill writes the design of one change as one interactive page. It is a copy of commit `0d5dd760` of github.com/AlmogBaku/visual-plan, without the README and the demo files. Five local changes are in `runtime/visualplan.js` and `runtime/visualplan.css`. The comment box of a table row opens in its own row. A missing list renders as an empty list. The Respond sheet can send its text to a waiter. The Send button turns gray while no waiter listens. Each part of a decision context starts a new line. Codex loads `~/.agents/skills` by itself, and `agy` loads it through `~/.gemini/config/skills.json`. Claude Code gets the files through one-line `include` templates in `dot_claude/skills/visual-plan/`. To update, compare a new upstream commit with this folder, and keep the changes |
| `~/.config/agent-hooks/visual-plan-pack.mjs` | `dot_config/agent-hooks/visual-plan-pack.mjs` | Claude Code runs it after each edit of a plan file in plan mode. It packs the `yaml visual-plan` block of the plan file into a page beside the plan file. Outside plan mode, every agent runs it with the path of a `plan.yaml`. If a waiter can deliver the response, it adds the Send button. The waiter wakes Claude Code and `agy`, and it pastes into the cmux pane of Codex. Outside cmux, a Codex `Stop` hook delivers the response. It rejects a page over 600 words plus 200 for each open decision. It also runs the page runtime in Node with a stub browser. It renders the main page and each zoom, and it rejects a page that crashes. When the simple-english plugin is installed, it adds the hits of the plugin's linter as warnings. The hook entry goes in `~/.claude/settings.json`, and other hooks stay. The global rules tell each agent how to use the skill |
| `~/.config/agent-hooks/visual-plan-wait.mjs` | `dot_config/agent-hooks/visual-plan-wait.mjs` | The response waiter of a visual plan page. When the pack hook asks for it, the agent starts it in the background. It listens on `127.0.0.1`, on a random port from 20000 to 32767 that the hook saves beside the plan file. At its start, it opens the page, so Send works from the first moment. The Send button of the page posts the response with a token. The waiter prints the response and ends, and Claude Code or `agy` then wakes the agent with it. With `--paste`, it types the response into the cmux pane of Codex instead. It has no time limit, so it never wakes an idle agent. It ends by itself after its agent session ends |
| `~/.config/agent-hooks/visual-plan-codex.mjs` | `dot_config/agent-hooks/visual-plan-codex.mjs` | Codex runs it from `~/.codex/hooks.json`, because the Codex sandbox blocks the waiter inside a Codex command. Inside cmux, Codex runs it after each tool call. After a run of the visual-plan pack command, it starts the waiter with `--paste`. Outside cmux, Codex runs it with `stop` at the end of a turn. Then it waits for the response, and it gives the response back as the next prompt. The session stays busy until then, and Esc ends the wait. It passes the ID of the Codex process, so the waiter ends with the session. Codex runs a new or changed hook only after you approve it once in `/hooks` |
| `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`, `~/.config/opencode/AGENTS.md` | `.chezmoitemplates/agent-rules.md` | Your global rules for Claude Code, Codex, the Antigravity CLI (`agy`) and opencode, from one template. Tool names differ per agent. When possible, the shared rules group necessary permission prompts and continue without blocked access. Each agent also gets the files in `~/.config/agent-rules/shared/`, then the files in its own folder there |
| `~/.codex/config.toml`, `~/.gemini/config/mcp_config.json` | `dot_codex/modify_private_config.toml`, `dot_gemini/config/modify_mcp_config.json` | MCP servers for Codex and `agy`: the list in `.chezmoidata/agents.yaml`, plus `agent_mcp_servers` from a work layer. chezmoi adds a missing server and changes nothing else. Each agent asks you to log in to a server the first time. Claude Code gets its servers from plugins, except the JetBrains IDE servers in the JetBrains row. In Codex, the template also sets the status line items, unless you picked your own with `/statusline`. On every apply it sets the approval mode closest to Claude Code's auto mode: commands run without asking, and the `auto_review` model answers each request for more access. It also moves the instructions of the nono pack above the first table, because Codex ignores them inside a table |
| `~/.gemini/antigravity-cli/settings.json` | `dot_gemini/antigravity-cli/modify_private_settings.json` | The `agy` status line, which runs `agent-statusline --agy`, and the full-screen mode (`"altScreenMode": "always"`), like Claude Code's `"tui": "fullscreen"`. It also adds each command of `agent_allowed_commands` in `.chezmoidata/agents.yaml` as a `command(...)` allow rule, the same list that Claude Code gets as `Bash(...)` rules. Two `read_file(...)` rules let `agy` read `~/.agents/skills` and `~/.gemini/config/skills` without a prompt. If `agentMode` is not set, it becomes `auto`, like the auto mode of Claude Code: commands run in the `agy` sandbox without a prompt, and risky ones still ask. A test showed that git over HTTPS and `glab` work in that sandbox. `agy` owns the rest of the file |
| `~/.config/opencode/opencode.json` | `dot_config/opencode/modify_opencode.json` | opencode gets the same MCP servers as Codex and `agy`, and the plugins in `.chezmoidata/agents.yaml`. By default it runs every command without asking, so a rule makes it ask before `git commit`, `git push` and `rm -rf`. chezmoi adds a missing entry and changes nothing else |
| Codex and `agy` plugins | `.chezmoiscripts/run_onchange_after_install-agent-plugins.*` | Installs the plugins in `.chezmoidata/agents.yaml`: superpowers for Codex and `agy`, and simple-english for Codex. It installs a missing plugin and changes nothing else. Codex asks you once to trust the simple-english hook |
| JetBrains IDE skills and MCP servers | `jetbrains_ides` in `.chezmoidata/agents.yaml`, `.chezmoitemplates/jetbrains-*`, `.chezmoiscripts/run_onchange_after_jetbrains-skills.*`, `.chezmoiscripts/run_onchange_after_claude-jetbrains-mcp.*`, `.chezmoiscripts/run_onchange_after_jetbrains-ports.*` | Every agent gets each installed JetBrains IDE as an MCP server, `jetbrains-<ide>` on the port in `jetbrains_ides`, and its bundled skills as `<ide>-<skill>`. An IDE counts as installed once it has run and made its cache folder. The skills script links each skill folder of the newest IDE version into `~/.claude/skills` and `~/.agents/skills`. It also removes its own links that the IDE no longer has. On Windows it copies the folders, because links need Developer Mode. The IDE rewrites its skill cache at each start, so a link always shows the current skill. Codex, `agy` and opencode get the servers through `agent_mcp_servers`. Claude Code gets them through `claude mcp add`. The ports script writes each port as `idea.mcp.server.force.port` into the `idea.properties` file of the newest IDE version. That line wins over the port on the MCP Server page of the IDE. The IDE reads it only at start, so restart the IDE after the script changes it. The rule "JetBrains IDE tools" in `agent-rules.md` gives an agent the conditions to start an IDE |
| `~/.jetbrains/acp.json` | `dot_jetbrains/modify_acp.json` | Adds three agents to JetBrains AI Assistant: "Claude Code (nono)" (`nclaude-acp`), "Codex (nono)" (`ncodex-acp`) and "OpenCode (nono)" (`nopencode-acp`). It keeps the agents that the IDE added. Not on Windows, which has no nono |
| `~/.config/ghostty/config` | `dot_config/ghostty/config` | Terminal configuration for cmux, the primary macOS terminal. cmux owns Ctrl-Cmd-Enter, so Warp keeps that global hotkey disabled on macOS |
| Warp `settings.toml`, `keybindings.yaml` | `dot_warp/` plus platform wrappers, defaults in `.chezmoitemplates/warp/` | Warp configuration and keybindings. chezmoi writes them to `~/.warp` on macOS, `~/.config/warp-terminal` on Linux and `%LOCALAPPDATA%\warp\Warp\config` on Windows. Linux and Windows use Ctrl-T for a new tab, Ctrl-Shift-T to reopen one, Ctrl-F4 to close one and Alt-Shift-[ or Alt-Shift-] to move between tabs. A new Windows machine uses Ctrl-Alt-Enter as Warp's global show/hide hotkey, and macOS leaves Ctrl-Cmd-Enter to cmux. Warp's cloud sync owns `settings.toml` once it exists: chezmoi writes the defaults only into a new file, and on Windows it adds the PowerShell startup shell, which Warp never syncs. Warp does not sync keybindings, so chezmoi owns `keybindings.yaml` |
| Windows Terminal `settings.json` | `AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/modify_settings.json` | Keeps discovered profiles and local additions. It owns the portable font, copy/paste, find, Ctrl-T and Ctrl-F4 behavior |
| PowerToys configuration | `AppData/Local/Microsoft/PowerToys/` | Keeps unknown and version-owned values. It syncs the enabled utilities and Keyboard Manager mappings. Warp owns Ctrl-Alt-Enter directly, so the old taskbar-position remap is removed |
| `~/.config/oh-my-posh/cli-theme.omp.json` | `dot_config/oh-my-posh/cli-theme.omp.json` | Oh My Posh prompt theme for PowerShell, zsh and bash 4.2 or later. Native Windows homes and Windows homes mounted in WSL use the Windows icon. Other homes keep their normal marker. AI agent shells do not load it. The terminal needs a Nerd Font for its glyphs. CI renders it on macOS, Linux and Windows |
| `~/.ssh/config` | `private_dot_ssh/private_config` | Loads `~/.ssh/config.d/*` first, then keeps key passphrases in the agent and the macOS keychain. Other systems skip the macOS-only option |
| `~/.gnupg/gpg-agent.conf` | `private_dot_gnupg/private_gpg-agent.conf.tmpl` | gpg-agent asks for a passphrase again after four idle hours, and at least every 12 hours. macOS uses the `pinentry-mac` dialog from Homebrew |
| `~/.config/chezmoi/chezmoi.toml` | `.chezmoi.toml.tmpl` | Your name, the work repo URL, and a `chezmoi diff` that shows files but not scripts. After a change, run `chezmoi init` |
| `~/.inputrc` | `dot_inputrc` | Bash line editing: case-insensitive completion, prefix history search on the arrow keys, word and Home/End keys like in zsh |
| `~/.local/bin/` | `dot_local/bin/` | Utility scripts |
| `~/.hushlogin` | `empty_dot_hushlogin` | Suppress login MOTD |
| `~/.config/shell/tools/termux.sh` | `dot_config/shell/tools/termux.sh` | Termux only: `TMPDIR`, `USER`, the phone's .NET values, the start of the Termux:API app with each shell, and the `pkg` and cache steps of `update-all`. Other Termux branches live in each tool's own file |
| `~/scripts/` | `scripts/` | Termux only: the bootstrap, and the install and remove scripts for .NET, Claude Code, Codex and `agy` |
| `~/.local/bin/claude`, `codex`, `dotnet` | `dot_local/bin/` | Termux only: wrappers that run each tool through `termux-chroot`, and through glibc where the tool needs it |
| `~/.local/bin/termux-chroot-exec`, `termux-glibc-exec` | `dot_local/bin/` | Termux only: they run a command through `termux-chroot` or glibc with every argument unchanged. Inside the chroot they skip the second proot |
| `~/.shortcuts/` | `dot_shortcuts/` | Termux only: Termux:Widget shortcuts that open Claude Code |
| `~/.termux/termux.properties`, `~/.termux/shell`, `~/.termux/font.ttf` | `dot_termux/`, `.chezmoiscripts/run_onchange_after_install-font.sh.tmpl` | Termux only: the Termux settings, zsh as the Termux shell, and the prompt font |

## Scripts (`~/.local/bin/`)

| Script | Description |
|---|---|
| `warp-claude.sh` | Launch Claude Code in a new Warp window, on macOS, Linux and Windows (Git Bash) |
| `cmux-claude.sh` | Launch Claude Code in a cmux workspace (`--agent-session` for cmux's native agent surface) |
| `rfv [query]` | Search file contents with ripgrep and pick a result in fzf, with a preview. Ctrl-T switches between ripgrep search and fzf filtering. Enter opens the file at that line in `$VISUAL` or `$EDITOR` (VS Code, Cursor, JetBrains IDEs, vim and others). Needs fzf 0.46 or later |
| `claude-reload`, `codex-reload`, `agy-reload` | Start the agent under a supervisor. A reload command then restarts the agent in the same session, and the update variant updates it first. In Claude Code, the commands are `/reload` and `/update-reload`. In Codex, they are the skills `$reload` and `$update-reload`. In `agy`, they are the skills `/reload` and `/update-reload`, because `agy` no longer loads workflows. `chezmoi apply` builds one program from `tools/agent-reload` with Go and installs it under the three names. The aliases `claude`, `codex` and `agy` run them, `cdx` is short for `codex`, `cdr` resumes a Codex session, `agr` continues the last `agy` conversation, and in cmux `automation.claudeBinaryPath` runs `claude-reload` |
| `work` | macOS, Linux and Termux. A shell whose work config lives in a temporary profile, which the end of the shell deletes. See "Work on a machine without the work layer" above |
| `update-all` | Update every package manager on this machine. See the next section |
| `clean-all` | Run `update-all --clean`: remove old Homebrew downloads and unused dependencies. A command run with `sudo` can leave root-owned files in an old Homebrew version. Then `clean-all` asks for your password and gives you those files, so `brew cleanup` can delete that version |
| `install-x64-homebrew` | macOS on Apple Silicon only. Installs the Intel Homebrew in `/usr/local` for packages that have no Apple Silicon build. After that, `xbrew` runs it and `update-all` updates it. Rosetta runs it through macOS 27, and Homebrew plans to end Intel support on September 1, 2027 |
| `update-chrome` | macOS only. Update Google Chrome with its own updater. `update-all` runs it before Homebrew |
| `agent-statusline` | The status line of Claude Code and `agy`: model, effort, context, cost, usage limits, folder, git branch and changed lines. Codex cannot run a command, so it shows its built-in items instead |
| `sclaude`, `scco`, `sccr`, `scodex`, `sopc`, `sccl`, `sccd` | Claude Code, Codex or opencode in a Docker sandbox (`sbx`). `sccl` lists and `sccd` deletes this folder's sandboxes. Codex signs in through an `sbx` secret, so run `sbx secret set -g openai` once |
| `nclaude`, `ncco`, `nccr`, `ncodex`, `nagy`, `nopc`, `nopr` | Claude Code, Codex, `agy` and opencode in a nono sandbox. All four share the tool grants in `.chezmoitemplates/nono-local-profile` and the egress allowlist. Run `nclaude -h` for the flags. Each needs its nono pack: `nono pull nolabs-ai/claude`, `nolabs-ai/codex`, `nolabs-ai/antigravity` or `nolabs-ai/opencode`. opencode runs with `--standalone`, so that its server runs in the sandbox too |
| `nclaude-acp`, `ncodex-acp`, `nopencode-acp` | Claude Code, Codex or opencode for an editor that hosts agents over ACP (JetBrains AI Assistant, Zed), in the same nono sandbox. They refuse to start in the home folder |
| `git-checkout-latest` (`gch`), `git-nuke` (`gnuke`), `git-unlock`, `git-worktrees-remove` | Git helpers. Git also runs them as `git nuke`, `git unlock` and so on. `gch [branch]` checks out the branch and pulls it. Without a branch, it uses the default branch of `origin`, or `main`, or `master`. `gchu [branch]` runs `git-unlock` first |

The chezmoi aliases in `~/.config/shell/tools/chezmoi.sh`:

| Alias | Runs |
|---|---|
| `czm` | `chezmoi` |
| `cza`, `czs`, `czd`, `czu` | `apply`, `status`, `diff` or `update` in each dotfiles layer (`chezmoi-private`, `chezmoi-work`), then in this repo, so its templates read the layers' data. Arguments go to this repo's command |
| `cze <file>` | `chezmoi edit`: edit the source of a target in `$EDITOR` |
| `czcd` | Go to this repo's source folder |

## Tool files

Each tool has one file in `~/.config/shell/tools`: `<tool>.sh` for zsh and bash, or `<tool>.zsh` for zsh only. `env.sh` turns each tool file into one shell function. Each phase calls all the functions in name order, and `$DOTFILES_PHASE` names the phase. A file handles only the phases it needs.

`env.sh` keeps the functions in a cache in `~/.cache/shell`, so a shell start opens one file instead of each tool file once per phase. If you change, add or remove a tool file, the next shell builds the cache again. If the cache folder is read-only, as in an agent sandbox, each shell builds the functions in memory.

| Phase | Who reads it | What goes there |
|---|---|---|
| `path` | `env.sh` | PATH entries only, with no command lookups |
| `env` | `env.sh` | Exports that can look up commands, because PATH is complete |
| `setup` | `.zshrc`, `.bashrc` | Interactive setup: completion, prompt, init scripts |
| `late` | `.zshrc`, `.bashrc` | Setup that builds on other tools' setup. For example, fzf wraps zoxide's completion for `cd` |
| `aliases` | `.zshrc`, `.bashrc` | Aliases. Read last, because zsh and bash expand an alias into every function defined after it |
| `update` | `update-all` | `_update_add <order> <name> <function>` registers an `update-all` step |
| `launcher` | `~/.local/bin` commands | The functions behind commands such as `nclaude` and `git-nuke` |

In a `.sh` file, the zsh-only code comes after the line `[ -n "${ZSH_VERSION:-}" ] || return 0`. The bash cache stops each file at that line, so zsh syntax after it never reaches bash.

## Packages

Package lists give a new machine the tools that these dotfiles call. Homebrew installs missing entries on apply. Windows installs are explicit, so a normal apply never installs a broad package set by surprise. No list upgrades or removes a package, and CI skips installs.

| System | List | Install command |
|---|---|---|
| macOS, Linux | `~/.config/homebrew/Brewfile`, plus each `*.Brewfile` that a work layer adds | `brew bundle install --no-upgrade --file <list>` |
| Windows GUI and system tools | `~/.config/winget/packages.json` | `Install-DotfilesPackages -Winget` in PowerShell |
| Windows portable CLIs | `~/.config/scoop/packages.json` | `Install-DotfilesPackages -Scoop` in PowerShell |
| PowerShell modules | `~/.config/powershell/modules.psd1` | `Install-DotfilesPackages -PowerShellModules` in PowerShell |
| Termux | `~/.config/termux/packages.txt` | `chezmoi apply` installs the missing ones with `pkg` |

Apps, casks and Mac App Store apps are in a macOS-only block of the Brewfile. The Mac App Store lines need you to be signed in to the App Store.

Scoop owns portable developer CLIs. Winget owns GUI and system-integrated software. Codex is a Scoop package. opencode uses its official npm package, and Antigravity uses Google's installer because neither supports a Windows package manager. Claude configuration stays usable, but no package list installs Claude. To install all tracked Windows packages deliberately, run `Install-DotfilesPackages -All`, or set `DOTFILES_INSTALL_PACKAGES=1` for one `chezmoi apply`.

After its Homebrew upgrade, `update-all` lists the packages that are installed but in no Brewfile, and the Brewfile entries that are not installed. It only reports. Add a package to a Brewfile with `chezmoi edit ~/.config/homebrew/Brewfile`, or remove it with `brew uninstall`.

Every Monday, and for each pull request or push to `main` that changes a list, CI runs `tools/package-check/check-package-lists.sh`. If a Homebrew package, tap, Mac App Store app, Winget ID or Scoop manifest is gone, deprecated or disabled, the check fails. A Termux package that the Termux main and glibc repositories lack also fails the check. To check a work Brewfile, run the same script with its path.

## Updating everything

`update-all` runs the `update` phase of every tool file and then the steps that the files registered. Each step checks its own condition. If its tool is not installed or has no repositories, the step does nothing. Tools that change the same package database count once. For example, `yum` runs only where `dnf` is missing, and paru or yay replaces pacman on Arch.

Steps run by order number, then by name. The order exists because some steps depend on others. Homebrew first upgrades `dotnet`, gcloud, nono and Claude Code, and then their own update commands run. Chrome's updater runs before Homebrew, so that Homebrew records the new version.

| Order | Steps |
|---|---|
| `10` | System packages: macOS `softwareupdate`, APT, DNF, YUM, rpm-ostree, Zypper, pacman, APK, XBPS, and Termux `pkg`. On Arch, paru or yay replaces pacman |
| `15`, `20` | Google Chrome (macOS), Homebrew (macOS and Linux, plus the Intel Homebrew on Apple Silicon), Flatpak, Snap, Nix |
| `30` | Google Cloud SDK, .NET global tools, nono packs, Claude Code plugins, opencode plugins. On Termux also Claude Code, Codex, `agy` and the .NET SDK, through the scripts in `~/scripts` |
| `90` | Dotfiles: if a fast-forward is possible, it pulls new commits and applies them. It never overwrites a file you edited, and it lists what still differs. A work layer adds its own step with the same helper |

- `update-all --dry-run` shows the steps for this machine and changes nothing.
- `update-all --skip-os-updates` skips the order `10` steps.
- `update-all brew claude` runs only the named steps.
- If no order `10` step applies on Linux, `update-all` prints one line that says so.
- On Termux, `update-all --clean` also clears the `pkg`, NuGet, npm, pip and Go caches and `$PREFIX/tmp`. It keeps a work profile in `$PREFIX/tmp/work-profile`.

## Checking a shell change

`tools/zsh-snapshot/zsh-snapshot.zsh` records what an interactive zsh defines: functions, aliases, options, PATH, hooks and key bindings. It records one shell as you and one shell as an AI agent sees it. chezmoi does not copy `tools/` to your home folder.

1. Run `zsh tools/zsh-snapshot/zsh-snapshot.zsh /tmp/before` in this repo.
2. Edit the source files and run `chezmoi apply`.
3. Run `zsh tools/zsh-snapshot/zsh-snapshot.zsh /tmp/after`.
4. Run `diff -ru /tmp/before /tmp/after`. Make sure that each difference is one you intended.

`tools/shell-check/fresh-home-check.sh` copies the shell files into an empty HOME, without zinit, caches or local files. It checks the syntax of every file and starts zsh and bash as you, as an AI agent and as a script. It tests every bash it finds, including macOS's bash 3.2. The check fails in two cases:

- A shell prints an error.
- zsh and bash differ in their environment, PATH or aliases.

GitHub Actions runs it for each pull request, and for each push to `main`, that changes a file that chezmoi applies. It runs on macOS, Ubuntu, five Linux distributions, Windows MSYS2, Windows Git Bash and Termux. The same workflow also runs the checks in `tools/ci/`. You can run them on your machine too:

| Script | What it tests |
|---|---|
| `check-templates.sh` | The Codex, opencode and `agy` modify templates with sample files from `tools/ci/fixtures/`. A second apply must change nothing. If `DOTFILES_INSTALL_PACKAGES=1` is set, the Windows install scripts must change, so that chezmoi runs them again |
| `check-rendered-files.sh` | Every JSON and TOML file in the rendered HOME parses. The check accepts comments in Zed's files |
| `check-statusline.sh` | `agent-statusline` with sample Claude Code and `agy` input, at full and narrow widths |
| `check-scripts.sh` | shellcheck at warning level on the standalone sh and bash scripts |
| `check-powershell.ps1` | Every PowerShell script and rendered Windows script parses and has no PSScriptAnalyzer error. `reload` replaces the functions, pwsh loads the profile once, the profile bridge keeps added lines, and no doskey macro calls another macro |
| `check-jetbrains.sh` | Fake Rider and GoLand folders in an empty HOME on macOS or Linux. The skills script links the newest version of each skill, keeps real folders and other links, and removes the links of a removed IDE. The ports script writes each port once. A fake `claude` gets each `mcp add`, and the Codex, opencode and `agy` templates get each server |
| `check-jetbrains.ps1` | The same fake folders on Windows, with marked copies instead of links, and a refresh of a changed skill |
| `check-git-bash-wrapper.sh` | In Git Bash, `update-all` and `clean-all` map their flags to PowerShell switches and stop on any other argument |

The workflow also lints the workflows with actionlint. Two more workflows run only when their files change, because most of their jobs need the macOS and Windows runners, which cost the most minutes: `powershell.yml` loads the profile in PowerShell on macOS, Ubuntu and Windows, and in Windows PowerShell 5.1, and `agent-reload.yml` runs the `agent-reload` Go tests on the same three systems.

A push to a branch runs nothing until the branch has a pull request, then a newer push cancels the run of the older one. A job stops after a few minutes, so a hung job does not hold a runner until its time limit.

The pre-push hook runs the same check on this machine before each push, in about 7 seconds. It also applies the repo to an empty HOME, so a template error stops the push. Then it runs the quick checks in `tools/ci`: rendered files, templates, the status line, and shellcheck where it is installed. On Termux, where every check runs several times slower, the hook skips the shell check and the status line check, which CI runs. It also skips the JetBrains check there, because no JetBrains IDE runs on Android. It still checks the forbidden terms, the apply, the rendered files and the templates. When a pushed commit changes a package list, the hook also runs the package check, which takes about a minute. To skip the hook once, push with `--no-verify`.

## Branches

Termux uses `main`, like every other system. The `android` branch is frozen, and nothing changes it.
