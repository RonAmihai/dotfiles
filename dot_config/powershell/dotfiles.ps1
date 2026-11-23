$script:DotfilesConfigHome = Split-Path -Parent $PSScriptRoot
$script:DotfilesIsWindows = $env:OS -eq 'Windows_NT'
$script:DotfilesAgentShell = @(
    'AI_AGENT', 'AGENT', 'CLAUDECODE', 'CLAUDE_CODE', 'CURSOR_AGENT', 'GEMINI_CLI',
    'CODEX_THREAD_ID', 'CODEX_SANDBOX', 'CODEX_CI', 'ANTIGRAVITY_AGENT',
    'ANTIGRAVITY_CLI_ALIAS', 'OPENCODE', 'OPENCODE_CLIENT', 'CLINE_ACTIVE',
    'GOOSE_PROVIDER', 'AUGMENT_AGENT', 'OPENCLAW_SHELL', 'JUNIE_DATA',
    'JUNIE_SHIM_PATH', 'COPILOT_MODEL', 'COPILOT_ALLOW_ALL'
) | Where-Object { [Environment]::GetEnvironmentVariable($_) } | Select-Object -First 1

function Add-DotfilesPath {
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }
    $separator = [IO.Path]::PathSeparator
    $comparison = if ($script:DotfilesIsWindows) {
        [StringComparison]::OrdinalIgnoreCase
    }
    else {
        [StringComparison]::Ordinal
    }
    $entries = @($env:PATH -split [regex]::Escape([string]$separator))
    if (-not ($entries | Where-Object { [string]::Equals($_, $Path, $comparison) })) {
        $env:PATH = "$Path$separator$env:PATH"
    }
}

Add-DotfilesPath (Join-Path $HOME '.local/bin')
if ($script:DotfilesIsWindows) {
    Add-DotfilesPath (Join-Path $HOME 'scoop/shims')
    Add-DotfilesPath (Join-Path $env:LOCALAPPDATA 'agy/bin')
    Add-DotfilesPath (Join-Path $env:APPDATA 'npm')
}

if (-not $env:EDITOR) {
    if (Get-Command nvim -ErrorAction SilentlyContinue) { $env:EDITOR = 'nvim' }
    elseif (Get-Command vim -ErrorAction SilentlyContinue) { $env:EDITOR = 'vim' }
    elseif (Get-Command code -ErrorAction SilentlyContinue) { $env:EDITOR = 'code --wait' }
}
if (-not $env:VISUAL -and $env:EDITOR) { $env:VISUAL = $env:EDITOR }

function Reload-Dotfiles {
    . (Join-Path $PSScriptRoot 'Microsoft.PowerShell_profile.ps1')
    # Functions that a script defines while a function dot-sources it stay local to that function
    Get-Command -CommandType Function |
        Where-Object { $_.ScriptBlock.File -and $_.ScriptBlock.File.StartsWith($PSScriptRoot) } |
        ForEach-Object { Set-Item -Path "function:global:$($_.Name)" -Value $_.ScriptBlock }
}

function Get-PublicIp {
    (Invoke-RestMethod -Uri 'https://api.ipify.org').Trim()
}

function New-Uuid {
    [guid]::NewGuid().ToString().ToLowerInvariant()
}

function ConvertTo-Lower {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline, Position = 0)] $InputObject)
    process { if ($null -ne $InputObject) { $InputObject.ToString().ToLowerInvariant() } }
}

function ConvertTo-Upper {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline, Position = 0)] $InputObject)
    process { if ($null -ne $InputObject) { $InputObject.ToString().ToUpperInvariant() } }
}

function Get-ChildItemLong {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        & eza --icons --group-directories-first -lah --header --git @args
    }
    else {
        Get-ChildItem -Force @args
    }
}

function Get-ChildItemAll {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        & eza --icons --group-directories-first -a @args
    }
    else {
        Get-ChildItem -Force @args
    }
}

function Get-ChildItemTree {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        & eza --icons --group-directories-first --tree --level=2 @args
    }
    else {
        Get-ChildItem -Recurse -Depth 2 @args
    }
}

function Initialize-GitSubmodules { & git submodule update --init --recursive @args }
function Update-GitSubmodules { & git submodule update --remote --merge --recursive @args }

function Get-GitDefaultBranch {
    $head = (& git symbolic-ref -q --short refs/remotes/origin/HEAD 2>$null) -join "`n"
    if ($head) { return $head -replace '^origin/', '' }
    foreach ($candidate in 'main', 'master') {
        & git show-ref -q "refs/heads/$candidate" "refs/remotes/origin/$candidate"
        if ($LASTEXITCODE -eq 0) { return $candidate }
    }
}

function Invoke-GitCheckoutLatest {
    [CmdletBinding()]
    param([Parameter(Position = 0)][string] $Branch)

    & git rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) { throw 'git-checkout-latest: not in a git repository' }
    if (-not $Branch) { $Branch = Get-GitDefaultBranch }
    if (-not $Branch) { throw 'git-checkout-latest: no branch given, and no origin/HEAD, main or master found' }
    $stashBefore = (& git rev-parse -q --verify refs/stash 2>$null) -join "`n"
    & git diff --quiet
    $dirty = $LASTEXITCODE -ne 0
    & git diff --cached --quiet
    $dirty = $dirty -or $LASTEXITCODE -ne 0
    if ($dirty) { & git stash push -m 'git-checkout-latest auto-stash' }
    & git checkout $Branch
    if ($LASTEXITCODE -ne 0) { return }
    & git pull
    if ($LASTEXITCODE -ne 0) { return }
    & git submodule update --init --recursive --force
    $stashAfter = (& git rev-parse -q --verify refs/stash 2>$null) -join "`n"
    if ($stashAfter -and $stashAfter -ne $stashBefore) {
        Write-Host 'Restoring stashed changes...'
        & git stash pop
    }
}

function Invoke-GitUnlock {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Position = 0, ValueFromRemainingArguments)][string[]] $Path = @($PWD.Path))

    $removed = 0
    foreach ($root in $Path) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            Write-Error "git-unlock: not a directory: $root"
            continue
        }
        $locks = Get-ChildItem -LiteralPath $root -Recurse -File -Force -Filter '*.lock' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '[\\/]\.git[\\/]' }
        foreach ($lock in $locks) {
            if (-not $PSCmdlet.ShouldProcess($lock.FullName, 'Remove git lock')) { continue }
            try { Remove-Item -LiteralPath $lock.FullName -Force -ErrorAction Stop }
            catch {
                Write-Error "git-unlock: failed to remove $($lock.FullName)"
                continue
            }
            Write-Host "removed  $($lock.FullName)"
            $removed++
        }
    }
    $noun = if ($removed -eq 1) { 'lock' } else { 'locks' }
    Write-Host "$removed git $noun removed"
}

function Invoke-GitUnlockCheckoutLatest {
    [CmdletBinding()]
    param([Parameter(Position = 0)][string] $Branch)

    Invoke-GitUnlock
    Invoke-GitCheckoutLatest -Branch $Branch
}

function Invoke-GitNuke {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param()

    $root = (& git rev-parse --show-toplevel 2>$null) -join "`n"
    if (-not $root) { throw 'git-nuke: not in a git repository' }
    & git -C $root status --short
    if (-not $PSCmdlet.ShouldProcess($root, 'Discard all tracked and untracked changes')) { return }
    & git -C $root reset --hard
    if ($LASTEXITCODE -ne 0) { return }
    & git -C $root clean -fd
    if ($LASTEXITCODE -ne 0) { return }
    & git -C $root submodule update --init --recursive --force
}

function Copy-DotfilesClipboard {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline)] $InputObject)
    begin { $items = @() }
    process { $items += $InputObject }
    end { $items | Set-Clipboard }
}

function Get-DotfilesClipboard { Get-Clipboard @args }

function Start-ClaudeIde { & claude --ide @args }
function Resume-ClaudeIde { & claude --ide --resume @args }
function Start-Codex { & codex @args }
function Resume-Codex { & codex resume @args }
function Resume-Antigravity { & agy --continue @args }

function Resume-OpenCode {
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        & opencode --continue @args
        return
    }

    $json = (& opencode session list --format json) -join "`n"
    if ($LASTEXITCODE -ne 0 -or -not $json) { return }
    try { $sessions = @($json | ConvertFrom-Json) }
    catch {
        & opencode --continue @args
        return
    }

    $rows = @($sessions | ForEach-Object {
        $updated = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$_.updated).LocalDateTime.ToString('dd/MM HH:mm')
        $title = if ($_.title) { $_.title } else { 'untitled' }
        "$($_.id)`t$updated`t$title"
    })
    $selected = ($rows | & fzf --delimiter "`t" --with-nth '2..' --prompt 'session> ') -join "`n"
    if ($LASTEXITCODE -ne 0 -or -not $selected) { return }
    $id = ($selected -split "`t", 2)[0]
    & opencode --session $id @args
}

function Start-WorkClaudeIde { & work cco @args }
function Resume-WorkClaudeIde { & work ccr @args }
function Start-WorkCodex { & work cdx @args }
function Resume-WorkCodex { & work cdr @args }
function Start-WorkAntigravity { & work agy @args }
function Resume-WorkAntigravity { & work agr @args }
function Start-WorkOpenCode { & work opc @args }
function Resume-WorkOpenCode { & work opr @args }

function Edit-Dotfiles { & chezmoi edit @args }

function Invoke-ChezmoiLayers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string] $Subcommand,
        [Parameter(ValueFromRemainingArguments)][object[]] $ArgumentList
    )

    $bin = Join-Path $HOME '.local/bin'
    $layers = @(Get-ChildItem -Path (Join-Path $bin 'chezmoi-*') -File -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($layer in $layers) {
        Write-Host "== $($layer.BaseName)"
        & $layer.FullName $Subcommand @ArgumentList
        if ($LASTEXITCODE -ne 0) { return }
    }
    Write-Host '== chezmoi'
    & chezmoi $Subcommand @ArgumentList
}

function Update-DotfilesShellAfterApply {
    [CmdletBinding()]
    param([Parameter(Mandatory)][datetime] $Since)

    $profileRoot = Join-Path $HOME '.config/powershell'
    $changed = Get-ChildItem -LiteralPath $profileRoot -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTimeUtc -gt $Since } |
        Select-Object -First 1
    if (-not $changed) { return }

    $interactive = -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
    if ($script:DotfilesAgentShell -or -not $interactive) {
        Write-Host 'The PowerShell config changed: run reload, or open a new terminal, to load it'
        return
    }
    if (@(Get-Job -State Running -ErrorAction SilentlyContinue).Count -gt 0) {
        Write-Host 'The PowerShell config changed: run reload when your background jobs end'
        return
    }
    Write-Host 'The PowerShell config changed, so it reloads'
    Reload-Dotfiles
}

function Invoke-ChezmoiLayersThenReload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string] $Subcommand,
        [Parameter(ValueFromRemainingArguments)][object[]] $ArgumentList
    )

    $marker = New-TemporaryFile
    try {
        Invoke-ChezmoiLayers $Subcommand @ArgumentList
        $exitCode = $global:LASTEXITCODE
        Update-DotfilesShellAfterApply -Since $marker.LastWriteTimeUtc
        $global:LASTEXITCODE = $exitCode
    }
    finally {
        Remove-Item -LiteralPath $marker.FullName -Force -ErrorAction SilentlyContinue
    }
}

function Apply-Dotfiles { Invoke-ChezmoiLayersThenReload apply @args }
function Get-DotfilesStatus { Invoke-ChezmoiLayers status @args }
function Compare-Dotfiles { Invoke-ChezmoiLayers diff @args }
function Update-Dotfiles { Invoke-ChezmoiLayersThenReload update @args }

function Set-DotfilesSourceLocation {
    $source = (& chezmoi source-path) -join "`n"
    if ($LASTEXITCODE -eq 0 -and $source) { Set-Location -LiteralPath $source }
}

function Test-DotfilesMachine {
    $source = (& chezmoi source-path) -join "`n"
    if ($LASTEXITCODE -ne 0 -or -not $source) { return }
    & bash (Join-Path $source 'tools/shell-check/check-this-machine.sh') @args
}

function Initialize-DotfilesCommandAliases {
    $agentReloadAliases = @{
        claude = 'claude-reload'
        codex = 'codex-reload'
        agy = 'agy-reload'
    }
    foreach ($name in $agentReloadAliases.Keys) {
        if (Get-Command $agentReloadAliases[$name] -ErrorAction SilentlyContinue) {
            Set-Alias $name $agentReloadAliases[$name] -Scope Global -Force
        }
    }

    $commandAliases = @{
        cco = 'Start-ClaudeIde'
        ccr = 'Resume-ClaudeIde'
        cdx = 'Start-Codex'
        cdr = 'Resume-Codex'
        agr = 'Resume-Antigravity'
        opc = 'opencode'
        opr = 'Resume-OpenCode'
        czm = 'chezmoi'
        cze = 'Edit-Dotfiles'
        cza = 'Apply-Dotfiles'
        czs = 'Get-DotfilesStatus'
        czd = 'Compare-Dotfiles'
        czu = 'Update-Dotfiles'
        czcd = 'Set-DotfilesSourceLocation'
        czcheck = 'Test-DotfilesMachine'
    }
    foreach ($name in $commandAliases.Keys) {
        if (Get-Command $commandAliases[$name] -ErrorAction SilentlyContinue) {
            Set-Alias $name $commandAliases[$name] -Scope Global -Force
        }
    }

    if (Get-Command work -ErrorAction SilentlyContinue) {
        $workAliases = @{
            wcco = 'Start-WorkClaudeIde'
            wccr = 'Resume-WorkClaudeIde'
            wcdx = 'Start-WorkCodex'
            wcdr = 'Resume-WorkCodex'
            wagy = 'Start-WorkAntigravity'
            wagr = 'Resume-WorkAntigravity'
            wopc = 'Start-WorkOpenCode'
            wopr = 'Resume-WorkOpenCode'
        }
        foreach ($name in $workAliases.Keys) {
            Set-Alias $name $workAliases[$name] -Scope Global -Force
        }
    }
}

if ($script:DotfilesIsWindows) {
    $windowsProfile = Join-Path $PSScriptRoot 'windows.ps1'
    if (Test-Path -LiteralPath $windowsProfile) { . $windowsProfile }
}
else {
    function Update-All {
        $script = Join-Path $HOME '.local/bin/update-all'
        if (-not (Test-Path -LiteralPath $script)) { throw "update-all: missing $script" }
        if (-not (Get-Command zsh -ErrorAction SilentlyContinue)) { throw 'update-all: zsh is not installed' }
        & zsh $script @args
    }
    function Clean-All {
        $script = Join-Path $HOME '.local/bin/clean-all'
        if (-not (Test-Path -LiteralPath $script)) { throw "clean-all: missing $script" }
        & sh $script @args
    }
}

$interactive = -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
if ($interactive) {
    if (-not $script:DotfilesAgentShell) {
        $optionalModules = 'npm-completion', 'yarn-completion'
        foreach ($module in $optionalModules) {
            Import-Module $module -ErrorAction SilentlyContinue
        }

        Import-Module PSReadLine -ErrorAction SilentlyContinue
        if (Get-Module PSReadLine) {
            try {
                Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction Stop
                Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction Stop
            }
            catch {}
        }

        if (Get-Command dotnet -ErrorAction SilentlyContinue) {
            Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
                param($wordToComplete, $commandAst, $cursorPosition)
                dotnet complete --position $cursorPosition $commandAst.ToString() | ForEach-Object {
                    [Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                }
            }
        }

        if ($script:DotfilesIsWindows) {
            $scoopCompletion = Join-Path $HOME 'scoop/apps/scoop-completion/current/scoop-completion.psd1'
            if (Test-Path -LiteralPath $scoopCompletion) {
                Import-Module $scoopCompletion -ErrorAction SilentlyContinue
            }
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
                    param($wordToComplete, $commandAst, $cursorPosition)
                    [Console]::InputEncoding = [Console]::OutputEncoding = $OutputEncoding = [Text.Utf8Encoding]::new()
                    $word = $wordToComplete.Replace('"', '""')
                    $ast = $commandAst.ToString().Replace('"', '""')
                    winget complete --word="$word" --commandline "$ast" --position $cursorPosition |
                        ForEach-Object { [Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
                }
            }
        }

        $theme = Join-Path $script:DotfilesConfigHome 'oh-my-posh/cli-theme.omp.json'
        if ((Get-Command oh-my-posh -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $theme)) {
            $previousOutputEncoding = [Console]::OutputEncoding
            [Console]::OutputEncoding = [Text.Encoding]::UTF8
            try { oh-my-posh init pwsh --config $theme | Invoke-Expression }
            finally { [Console]::OutputEncoding = $previousOutputEncoding }
        }
    }

    Set-Alias reload Reload-Dotfiles -Scope Global
    Set-Alias refresh Reload-Dotfiles -Scope Global
    Set-Alias rr Reload-Dotfiles -Scope Global
    Set-Alias get-ip Get-PublicIp -Scope Global
    Set-Alias uid New-Uuid -Scope Global
    Set-Alias lower ConvertTo-Lower -Scope Global
    Set-Alias upper ConvertTo-Upper -Scope Global
    Set-Alias ll Get-ChildItemLong -Scope Global
    Set-Alias la Get-ChildItemAll -Scope Global
    Set-Alias lt Get-ChildItemTree -Scope Global
    Set-Alias git-submodules-init Initialize-GitSubmodules -Scope Global
    Set-Alias git-submodules-update Update-GitSubmodules -Scope Global
    Set-Alias gch Invoke-GitCheckoutLatest -Scope Global
    Set-Alias gchu Invoke-GitUnlockCheckoutLatest -Scope Global
    Set-Alias git-unlock Invoke-GitUnlock -Scope Global
    Set-Alias gnuke Invoke-GitNuke -Scope Global
    Set-Alias ua Update-All -Scope Global
    Set-Alias ca Clean-All -Scope Global
    Set-Alias pbcopy Copy-DotfilesClipboard -Scope Global
    Set-Alias pbpaste Get-DotfilesClipboard -Scope Global
    Set-Alias which Get-Command -Scope Global

    $aliases = @{
        cat = 'bat'
        grep = 'rg'
        vi = 'nvim'
        k = 'kubectl'
        lg = 'lazygit'
        ff = 'fastfetch'
    }
    foreach ($name in $aliases.Keys) {
        if (Get-Command $aliases[$name] -ErrorAction SilentlyContinue) {
            Set-Alias $name $aliases[$name] -Scope Global -Force
        }
    }
    Initialize-DotfilesCommandAliases
    if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
        Set-Alias nf fastfetch -Scope Global
        Set-Alias neofetch fastfetch -Scope Global
    }
    elseif (Get-Command winfetch -ErrorAction SilentlyContinue) {
        Set-Alias nf winfetch -Scope Global
        Set-Alias neofetch winfetch -Scope Global
    }
    if ($script:DotfilesIsWindows -and (Get-Command gsudo -ErrorAction SilentlyContinue)) {
        Set-Alias sudo gsudo -Scope Global -Force
    }
}

$localProfile = Join-Path $PSScriptRoot 'local.ps1'
if (Test-Path -LiteralPath $localProfile) { . $localProfile }
