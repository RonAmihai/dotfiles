# Not profile.ps1: pwsh on macOS and Linux loads that name from this folder by itself
$profileCore = Join-Path $PSScriptRoot 'dotfiles.ps1'
if (Test-Path -LiteralPath $profileCore) {
    . $profileCore
}
