# Usage: pwsh tools/ci/check-powershell.ps1 -Chezmoi PATH -Config PATH -RenderedHome DIR — parses and analyzes every PowerShell script, and tests reload, the single profile load, the Windows profile bridge and the cmd macros
param(
    [Parameter(Mandatory)][string] $Chezmoi,
    [Parameter(Mandatory)][string] $Config,
    [Parameter(Mandatory)][string] $RenderedHome
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$pwsh = (Get-Process -Id $PID).Path
$work = Join-Path ([IO.Path]::GetTempPath()) "check-powershell-$PID"
New-Item -ItemType Directory -Force -Path $work | Out-Null

# The Windows scripts render empty while CI is set
Remove-Item Env:CI -ErrorAction SilentlyContinue
$windowsData = if ($IsWindows) { @() } else { @('--override-data', '{"chezmoi":{"os":"windows"}}') }
$scripts = @(& git -C $repo ls-files '*.ps1' | ForEach-Object { Join-Path $repo $_ })
foreach ($template in Get-ChildItem (Join-Path $repo '.chezmoiscripts') -Filter '*.ps1.tmpl') {
    $rendered = Join-Path $work ($template.Name -replace '\.tmpl$', '')
    & $Chezmoi --config $Config --source $repo execute-template @windowsData --file $template.FullName | Set-Content $rendered
    if ($LASTEXITCODE -ne 0) { throw "could not render $($template.Name)" }
    $scripts += $rendered
}

foreach ($script in $scripts) {
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$errors) | Out-Null
    if ($errors) { throw "$script does not parse: $($errors[0].Message)" }
}
Write-Host "check-powershell: $($scripts.Count) scripts parse"

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
}
$problems = @($scripts | ForEach-Object { Invoke-ScriptAnalyzer -Path $_ -Severity Error })
if ($problems) {
    $problems | Format-Table ScriptName, Line, RuleName, Message -AutoSize | Out-String -Width 250 | Write-Host
    throw 'PSScriptAnalyzer found errors'
}
Write-Host 'check-powershell: PSScriptAnalyzer found no errors'

$profileCopy = Join-Path $work 'powershell'
Copy-Item (Join-Path $RenderedHome '.config/powershell') $profileCopy -Recurse
$reloaded = @(& $pwsh -NoLogo -NoProfile -Command ". '$(Join-Path $PSScriptRoot 'powershell-reload-test.ps1')' '$profileCopy'")
if ($reloaded[-1] -ne 'reloaded') { throw "Reload-Dotfiles kept the old functions: $($reloaded -join ' ')" }
Write-Host 'check-powershell: Reload-Dotfiles replaces the functions'

if (-not $IsWindows) {
    $loadHome = Join-Path $work 'home'
    New-Item -ItemType Directory -Force -Path (Join-Path $loadHome '.config') | Out-Null
    Copy-Item (Join-Path $RenderedHome '.config/powershell') (Join-Path $loadHome '.config/powershell') -Recurse
    Set-Content (Join-Path $loadHome '.config/powershell/local.ps1') '$global:DotfilesLoads++'
    $savedHome, $savedXdg = $env:HOME, $env:XDG_CONFIG_HOME
    $env:HOME = $loadHome
    Remove-Item Env:XDG_CONFIG_HOME -ErrorAction SilentlyContinue
    try { $loads = & $pwsh -NoLogo -Command '$global:DotfilesLoads' }
    finally {
        $env:HOME = $savedHome
        if ($savedXdg) { $env:XDG_CONFIG_HOME = $savedXdg }
    }
    if ("$loads" -ne '1') { throw "pwsh loaded the dotfiles profile $loads times instead of once" }
    Write-Host 'check-powershell: pwsh loads the dotfiles profile once'
}

if ($IsWindows) {
    $documents = [Environment]::GetFolderPath('MyDocuments')
    $coreProfile = Join-Path $documents 'PowerShell\Microsoft.PowerShell_profile.ps1'
    $desktopProfile = Join-Path $documents 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
    $bridge = '. "$HOME\.config\powershell\Microsoft.PowerShell_profile.ps1"'
    New-Item -ItemType Directory -Force -Path (Split-Path $coreProfile), (Split-Path $desktopProfile) | Out-Null
    Set-Content $coreProfile "$bridge`n# added later"
    Set-Content $desktopProfile 'Write-Output custom'
    try {
        & $pwsh -NoLogo -NoProfile -File (Join-Path $work 'run_onchange_after_powershell-profile.ps1')
        if (-not (Get-Content -Raw $coreProfile).Contains('# added later')) { throw 'the profile bridge script dropped lines added after the bridge' }
        if (-not (Get-Content -Raw $desktopProfile).Contains($bridge)) { throw 'the profile bridge script did not write the bridge' }
        $backups = Get-ChildItem (Split-Path $desktopProfile) -Filter 'Microsoft.PowerShell_profile.ps1.pre-chezmoi*.bak'
        if (-not ($backups | Where-Object { (Get-Content -Raw $_.FullName).Contains('custom') })) { throw 'the profile bridge script did not back up the old profile' }
    }
    finally {
        Remove-Item $coreProfile, $desktopProfile -Force -ErrorAction SilentlyContinue
        Get-ChildItem (Split-Path $desktopProfile) -Filter '*.pre-chezmoi*.bak' | Remove-Item -Force
    }
    Write-Host 'check-powershell: the profile bridge keeps added lines and backs up a foreign profile'

    $cmdProfile = Get-Content -Raw (Join-Path $RenderedHome '.config/cmd/profile.cmd')
    if ($cmdProfile -match '(?m)^doskey \w+=(reload|refresh|rr)\s*$') { throw "a doskey macro calls another macro, which doskey never expands: $($Matches[0])" }
    if ($cmdProfile -match '(?m)^\s*where(\.exe)?\s') { throw "the cmd profile starts where.exe: $($Matches[0])" }
    Write-Host 'check-powershell: no doskey macro calls another macro, and the profile starts no where.exe'

    # A variable named CMDCMDLINE hides the dynamic one, so the test can play an interactive cmd and a "cmd /c"
    $autorunTest = Join-Path $work 'autorun-test.cmd'
    $localBin = Join-Path $RenderedHome '.local\bin'
    Set-Content $autorunTest "@echo off`r`nset `"USERPROFILE=$RenderedHome`"`r`nset `"CMDCMDLINE=%~1`"`r`ncall `"$(Join-Path $RenderedHome '.config\cmd\autorun.cmd')`"`r`nset PATH"
    $interactivePath = (& cmd.exe /d /c $autorunTest 'cmd.exe') -join "`n"
    $batchPath = (& cmd.exe /d /c $autorunTest 'cmd.exe /c build') -join "`n"
    if (-not $interactivePath.Contains($localBin)) { throw 'AutoRun did not load the cmd profile in an interactive cmd' }
    if ($batchPath.Contains($localBin)) { throw 'AutoRun loaded the cmd profile for "cmd /c"' }
    Write-Host 'check-powershell: AutoRun loads the cmd profile only in an interactive cmd'

    $entry = Join-Path $RenderedHome '.config/powershell/Microsoft.PowerShell_profile.ps1'
    $compiled = @(& $pwsh -NoLogo -NoProfile -Command ". '$entry'; 'before=' + [bool]('WindowRescue.NativeMethods' -as [type]); Restore-Windows; 'after=' + [bool]('WindowRescue.NativeMethods' -as [type])")
    if (-not ($compiled -contains 'before=False' -and $compiled -contains 'after=True')) { throw "the window helper is not compiled on first use: $($compiled -join ' ')" }
    Write-Host 'check-powershell: the window helper compiles on its first use'
}
