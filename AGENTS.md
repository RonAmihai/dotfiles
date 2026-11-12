# Rules for AI agents in this repo

This repo is the chezmoi source of a personal dotfiles setup. It runs on macOS, Linux, WSL2, Git Bash, MSYS2, native Windows and Termux on Android. The README explains each part. This file lists the rules that an agent must follow.

## Never

- Never put anything about an employer in this repo: company names, work emails, hosts, account IDs or internal tools. Work files belong in the separate work repo in `~/.local/share/chezmoi-work`. The pre-push hook blocks a push that contains a work term.
- Never edit a target file in the home folder. chezmoi overwrites it on the next apply. Edit the source in this repo, then run `chezmoi apply`.
- Never commit or push unless the user asks for it in the current task. A request to commit does not include a push.
- Never rewrite history.
- Never delete user data with `rm -rf`. Move it to the Trash, and list what goes before a bulk removal.
- Never read, print or commit a secret. Secrets stay in a login or in a local file outside every repo, and the code reads them at run time.

## Where things go

- Each shell tool has one file in `dot_config/shell/tools/`. Use `<tool>.sh` for zsh and bash, or `<tool>.zsh` for zsh only. The README section "Tool files" explains the phases.
- In a `.sh` tool file, zsh-only code goes after the line `[ -n "${ZSH_VERSION:-}" ] || return 0`. The part before that line must work in bash 3.2.
- An `update-all` step is a function that a tool file registers with `_update_add <order> <name> <function>`.
- Packages go in `dot_config/homebrew/Brewfile` for macOS and Linux. Windows GUI/system packages go in `dot_config/winget/packages.json`; portable CLIs go in `dot_config/scoop/packages.json`. Termux packages go in `dot_config/termux/packages.txt`.
- A file for one system only needs a rule in `.chezmoiignore`. Windows targets live under `AppData/`. A Termux-only file needs a rule in the not-Android block.
- Termux shell code goes in the tool file that owns the tool, behind `$OSTYPE == linux-android*`. `termux.sh` holds only what belongs to Termux itself: `pkg`, `TMPDIR`, `USER`, the phone's .NET values and the start of the Termux:API app.
- If a change alters behavior on another system on purpose, add each changed rendered file to `tools/ci/render-diff-allowed.txt`.
- A setup script is a `.sh.tmpl` or `.ps1.tmpl` file in `.chezmoiscripts/`. On the other systems, and while `CI` is set, each script renders empty.

## Coding agents

Share a setting with every agent where the agents allow it. Give an agent its own setting only for what differs.

- Global rules for every agent go in `.chezmoitemplates/agent-rules.md`. A rule for one agent goes in a `{{ if eq .agent "..." }}` block, or in a file in `dot_config/agent-rules/<agent>/`.
- A rule file for every agent goes in `dot_config/agent-rules/shared/`.
- MCP servers for Codex and `agy` go in `.chezmoidata/agents.yaml`.
- A JetBrains IDE goes in `jetbrains_ides` in `.chezmoidata/agents.yaml`. Every agent gets its MCP server and its skills from that entry.
- Commands that agents run without a prompt come from `agent_allowed_commands`, and commands that chezmoi removes from the agents' settings come from `agent_retired_commands`. Both lists stay empty in `.chezmoidata/agents.yaml`. A layer adds its own in `~/.config/chezmoi/data.d/`, and Claude Code and `agy` both read the merged lists. A layer adds a command only when no option of it can start a program or write a file.
- Hook scripts go in `dot_config/agent-hooks/`. Each agent's settings template registers them.
- A skill for every agent goes in `dot_agents/skills/`. Codex reads `~/.agents/skills` by itself, and `agy` reads it through `dot_gemini/config/skills.json.tmpl`. Claude Code needs one-line `include` templates in `dot_claude/skills/`.
- The agents are `claude`, `codex` and `antigravity`.

## PowerShell

The shared PowerShell Core profile lives in `dot_config/powershell/`. Keep it cross-platform and compatible with Windows PowerShell 5.1. Put Windows-only code in `windows.ps1` or the lowercase `windows/` folder.

- OneDrive can move the Documents folder. The Windows setup script asks PowerShell for the Documents folder and writes a small bridge instead of using a fixed path.
- Windows PowerShell 5.1 reads a UTF-8 file without a BOM as ANSI. Keep the shared files ASCII. The setup script writes its bridge with a BOM.
- PowerShell 7 reads `~/.config/powershell` directly on macOS and Linux. The PowerShell CI matrix must load the profile from an empty home on all three systems.

## Checks

1. Before a shell change, run `zsh tools/zsh-snapshot/zsh-snapshot.zsh /tmp/before`. After it, run the script again with `/tmp/after`, then compare the two folders.
2. Run `bash tools/shell-check/fresh-home-check.sh`. Every line must start with `ok:`.
3. If you change a package list, run `bash tools/package-check/check-package-lists.sh` with the list's path.
4. If you change a Termux file, render the repo into an empty HOME in the `termux/termux-docker` image, then run `bash tools/ci/check-termux.sh` on that HOME.
5. The pre-push hook runs these checks on the pushed commit. Do not skip it with `--no-verify`.

## Style

- Write comments only for logic that stays unclear. Keep each comment to one line.
- Write the README in plain English: short sentences, active voice, and the condition before the command.
- Keep LF line endings. `.gitattributes` enforces them.
