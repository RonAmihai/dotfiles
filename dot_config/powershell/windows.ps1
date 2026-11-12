$restoreWindows = Join-Path $PSScriptRoot 'windows/restore-windows.ps1'
if (Test-Path -LiteralPath $restoreWindows) { . $restoreWindows }

function Install-DotfilesPackages {
    [CmdletBinding()]
    param(
        [switch] $Winget,
        [switch] $Scoop,
        [switch] $PowerShellModules,
        [switch] $All
    )

    if (-not ($Winget -or $Scoop -or $PowerShellModules -or $All)) {
        throw 'Choose -Winget, -Scoop, -PowerShellModules, or -All. Package installs are explicit.'
    }
    if ($All -or $Winget) {
        $manifest = Join-Path $HOME '.config/winget/packages.json'
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'winget is not installed' }
        winget import --import-file $manifest --no-upgrade --ignore-unavailable --accept-package-agreements --accept-source-agreements
    }
    if ($All -or $Scoop) {
        $manifest = Join-Path $HOME '.config/scoop/packages.json'
        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { throw 'Scoop is not installed' }
        scoop import $manifest
    }
    if ($All -or $PowerShellModules) {
        $manifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'modules.psd1')
        foreach ($module in $manifest.Modules) {
            if (-not (Get-Module -ListAvailable -Name $module)) {
                Install-Module -Name $module -Scope CurrentUser -Repository PSGallery -Force
            }
        }
    }
}

function Update-All {
    [CmdletBinding()]
    param(
        [switch] $SkipOSUpdates,
        [switch] $DryRun,
        [switch] $NativePackagesOnly,
        [switch] $WindowsSystemOnly,
        [switch] $SkipWSL,
        [switch] $SkipDotfiles
    )

    $failures = [Collections.Generic.List[string]]::new()
    $run = {
        param([string] $Name, [string] $Description, [scriptblock] $Action)
        if ($DryRun) {
            Write-Host "  would run: $Description"
            return
        }
        Write-Host "`n== $Name ==" -ForegroundColor Blue
        try { & $Action }
        catch {
            $failures.Add($Name)
            Write-Warning "$Name failed: $($_.Exception.Message)"
        }
    }
    $native = {
        param([string] $Command, [object[]] $Arguments)
        & $Command @Arguments
        if ($LASTEXITCODE -ne 0) { throw "$Command exited with code $LASTEXITCODE" }
    }

    if (-not $WindowsSystemOnly) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            & $run 'Winget Packages' 'winget upgrade --all' {
                & $native 'winget' @('upgrade', '--all', '--include-unknown', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
            }
        }
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            & $run 'Scoop Packages' 'scoop update; scoop update *' {
                & $native 'scoop' @('update')
                & $native 'scoop' @('update', '*')
            }
        }
        if (Get-Command Update-Module -ErrorAction SilentlyContinue) {
            & $run 'PowerShell Modules' 'Update-Module' {
                $update = @{ ErrorAction = 'Stop' }
                # The PowerShellGet that ships with Windows PowerShell 5.1 has no -AcceptLicense
                if ((Get-Command Update-Module).Parameters.ContainsKey('AcceptLicense')) { $update.AcceptLicense = $true }
                Update-Module @update
            }
        }
    }

    if (-not $NativePackagesOnly -and -not $WindowsSystemOnly) {
        if (Get-Command gcloud -ErrorAction SilentlyContinue) {
            & $run 'Google Cloud SDK' 'gcloud components update --quiet' {
                & $native 'gcloud' @('components', 'update', '--quiet')
            }
        }
        if (Get-Command dotnet -ErrorAction SilentlyContinue) {
            & $run '.NET Global Tools' 'dotnet tool update --global --all' {
                & $native 'dotnet' @('tool', 'update', '--global', '--all')
            }
        }
        if (Get-Command agy -ErrorAction SilentlyContinue) {
            & $run 'Antigravity CLI' 'agy update' { & $native 'agy' @('update') }
        }
        if (Get-Command nono -ErrorAction SilentlyContinue) {
            & $run 'nono Packs' 'nono update' { & $native 'nono' @('update') }
        }
        if (Get-Command opencode -ErrorAction SilentlyContinue) {
            if (Get-Command npm -ErrorAction SilentlyContinue) {
                & $run 'opencode' 'npm update --global @opencode/cli' {
                    & $native 'npm' @('update', '--global', '@opencode/cli')
                }
            }
            & $run 'opencode Plugins' 'opencode plugin update' {
                & $native 'opencode' @('plugin', 'update')
            }
        }
        if (Get-Command claude -ErrorAction SilentlyContinue) {
            & $run 'Claude Code' 'claude update' { & $native 'claude' @('update') }
            $plugins = @(& claude plugin list 2>$null | Select-String -AllMatches '[^\s]+@[^\s]+' | ForEach-Object { $_.Matches.Value } | Sort-Object -Unique)
            foreach ($plugin in $plugins) {
                & $run "Claude Plugin: $plugin" "claude plugin update $plugin" {
                    & $native 'claude' @('plugin', 'update', $plugin)
                }
            }
        }
    }

    if (-not $NativePackagesOnly -and -not $SkipOSUpdates) {
        $nativeUpdate = Join-Path $PSScriptRoot 'windows/update-windows-and-drivers.ps1'
        if (Test-Path -LiteralPath $nativeUpdate) {
            & $run 'Windows and Drivers' $nativeUpdate {
                $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
                $principal = [Security.Principal.WindowsPrincipal]::new($identity)
                if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                    & $nativeUpdate
                }
                elseif (Get-Command gsudo -ErrorAction SilentlyContinue) {
                    & $native 'gsudo' @('pwsh', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $nativeUpdate)
                }
                else {
                    Write-Warning "Run as administrator to apply Windows and driver updates: $nativeUpdate"
                }
            }
        }
        if (Get-Command wsl -ErrorAction SilentlyContinue) {
            & $run 'WSL Runtime' 'wsl --update' { & $native 'wsl' @('--update') }
        }
    }

    if (-not $NativePackagesOnly -and -not $WindowsSystemOnly) {
        if (-not $SkipWSL -and (Get-Command wsl -ErrorAction SilentlyContinue)) {
            $wslCommand = if ($DryRun) { 'update-all --dry-run' } else { 'update-all' }
            if ($SkipOSUpdates) { $wslCommand += ' --skip-os-updates' }
            & $run 'WSL Packages and Tools' "wsl --exec zsh -ic '$wslCommand'" {
                & $native 'wsl' @('--exec', 'zsh', '-ic', $wslCommand)
            }
        }
        if (-not $SkipDotfiles -and (Get-Command chezmoi -ErrorAction SilentlyContinue)) {
            & $run 'Dotfiles' 'chezmoi update --apply' {
                & $native 'chezmoi' @('update', '--apply')
            }
        }
    }

    if ($failures.Count) { throw "Update-All failed: $($failures -join ', ')" }
}

function Clean-All {
    [CmdletBinding()]
    param([switch] $NativeOnly, [switch] $DryRun)
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        if ($DryRun) { Write-Host '  would run: scoop cleanup *; scoop cache rm *' }
        else {
            scoop cleanup *
            scoop cache rm *
        }
    }
    if (-not $NativeOnly -and (Get-Command wsl -ErrorAction SilentlyContinue)) {
        $command = if ($DryRun) { 'update-all --clean --dry-run' } else { 'update-all --clean' }
        & wsl --exec zsh -ic $command
        if ($LASTEXITCODE -ne 0) { Write-Warning 'WSL clean-all was unavailable; apply the dotfiles inside WSL first.' }
    }
}
