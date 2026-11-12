# Termux

This is a Termux environment on Android (aarch64). Claude Code runs inside `termux-chroot`; the user's shell runs in standard Termux (non-chroot).

## Cloning Repositories

By default, clone repositories into `$TMPDIR`, so that no repository stays on the device after the session. Push all work before the session ends.

Only clone into a permanent location (e.g. `~/projects/`) if the user explicitly asks.

For work, run `work`. It keeps work config in a temporary profile.

## Environment Rules

**NEVER install or update native binaries (dotnet, claude, etc.) manually.** Standard Linux ELF binaries do not run on Android's bionic libc — they must be patched with `glibc-runner` after installation. Manual installs will break the user's shell.

Always use the provided scripts in `~/scripts/`:
- **dotnet-update.sh [channel|version]** — install/update .NET SDK (e.g., `dotnet-update.sh 9.0` for latest 9.0, `dotnet-update.sh 9.0.311` for exact version, or `dotnet-update.sh` for latest LTS)
- **claude-setup.sh** — install/update Claude Code
- **codex-setup.sh** — install/update Codex CLI (official standalone package from GitHub releases, installed to `~/.codex/packages/standalone`; runs via `termux-chroot` wrapper — the TUR package is far behind upstream)
- **agy-setup.sh** — install/update Antigravity CLI (native Android build; don't use the official install.sh — inside the chroot it picks the glibc build and edits shell profiles)
- **update-all** (bash alias `ua`) — update everything

Android device storage is accessible at `~/storage/`. To view images (screenshots, photos, etc.), find them with `ls -t` and read directly.

When installing other tools: prefer `pkg install`. If only a Linux binary is available:
- Patch with `glibc-runner -c`
- Create a wrapper using `termux-chroot glibc-runner -n`
- Verify it works in the user's non-chroot shell
