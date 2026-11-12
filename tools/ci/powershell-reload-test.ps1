# Usage: pwsh -NoProfile -Command ". tools/ci/powershell-reload-test.ps1 CONFIG_DIR" — loads the profile at the global scope, edits New-Uuid, reloads, and prints what New-Uuid returns
$config = $args[0]
. (Join-Path $config 'Microsoft.PowerShell_profile.ps1')
$core = Join-Path $config 'dotfiles.ps1'
(Get-Content -Raw $core).Replace('[guid]::NewGuid().ToString().ToLowerInvariant()', "'reloaded'") | Set-Content $core
Reload-Dotfiles
New-Uuid
