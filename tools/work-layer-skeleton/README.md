# Work dotfiles

This repo is the work layer on top of the personal dotfiles. The `chezmoi-work` command applies it, with its own source folder (`~/.local/share/chezmoi-work`) and its own state.

## New machine

1. Install the personal dotfiles with `chezmoi init --apply <personal repo>`.
2. When `chezmoi init` asks for the work dotfiles repo, enter the URL of this repo.
3. After the first apply, a script clones this repo and applies it.
4. Run `chezmoi apply` once more, so the personal templates read the data that this repo added.

## What is included

| Target | What it does |
|---|---|
| `~/.config/git/work.gitconfig` | Repos with a work remote get the work identity |
| `~/.config/git/work-identity.gitconfig` | Work email. If the employer needs signed commits, add the signing keys here |
| `~/.claude/settings.json` | Adds work permissions, marketplaces and plugins, and keeps every other entry |
| `~/.config/chezmoi/data.d/work.json` | Data for the personal templates |
| `~/.config/chezmoi/forbidden-terms.d/work` | Employer terms that the personal repo's pre-push hook blocks. Replace the examples with the employer's name, domains and ticket keys |
| `~/.config/shell/tools/chezmoi-work.zsh` | Tool file with the `update-all` step that pulls this repo, applies it and lists what still differs. Add one tool file per work tool in this folder |
| `~/.local/bin/chezmoi-work` | The `chezmoi` command for this repo |

`.githooks/pre-push` checks zsh syntax, JSON files and template rendering, and stops a push on an error. The first apply turns it on for this clone.

No secret goes in this repo. Read secrets at run time, from a login or from a local file outside every repo.
