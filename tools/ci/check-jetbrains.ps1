# Usage: pwsh tools/ci/check-jetbrains.ps1 -Chezmoi PATH -Config PATH - builds fake JetBrains IDE folders in an empty home on Windows, runs the Windows JetBrains scripts on them, and fails on a wrong result
param(
    [Parameter(Mandatory)][string] $Chezmoi,
    [Parameter(Mandatory)][string] $Config
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$work = Join-Path ([IO.Path]::GetTempPath()) "check-jetbrains-$PID"
$fakeHome = Join-Path $work 'home'
$cache = Join-Path $fakeHome 'AppData\Local\JetBrains'
$conf = Join-Path $fakeHome 'AppData\Roaming\JetBrains'
$resources = 'ai-agent-extensions\bundledSkillsResources'
$bin = Join-Path $work 'bin'
$log = Join-Path $work 'claude.log'

function Stop-Check([string] $Message) { throw "check-jetbrains: $Message" }

function New-Skill([string] $Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    Set-Content -Path (Join-Path $Path 'SKILL.md') -Value "---`nname: $(Split-Path -Leaf $Path)`n---"
}

function Invoke-JetBrainsScript([string] $Name) {
    $rendered = Join-Path $work "$Name.ps1"
    $template = Join-Path $repo ".chezmoiscripts\run_onchange_after_$Name.ps1.tmpl"
    & $Chezmoi --config $Config --source $repo execute-template --file $template | Set-Content -Path $rendered
    if ($LASTEXITCODE -ne 0) { Stop-Check "could not render $Name" }
    & $rendered 3>&1 6>&1 | Out-String
}

function Test-Copy([string] $Path) {
    (Test-Path (Join-Path $Path 'SKILL.md')) -and (Test-Path (Join-Path $Path '.jetbrains-skill'))
}

New-Skill (Join-Path $cache "Rider2026.2\$resources\rider.provider\old-only")
New-Skill (Join-Path $cache "Rider2026.3\$resources\rider.provider\debugging-code")
New-Skill (Join-Path $cache "Rider2026.3\$resources\rider.provider\bundledSkills\rider-database-connection-management")
New-Skill (Join-Path $cache "Rider2026.3\$resources\cmake.provider\bundledSkills\cmake-project-configuration")
New-Skill (Join-Path $cache "GoLand2026.3\$resources\goland.provider\go-debug")
New-Item -ItemType Directory -Force -Path (Join-Path $conf 'Rider2026.3'), (Join-Path $conf 'GoLand2026.3') | Out-Null
$riderProperties = Join-Path $conf 'Rider2026.3\idea.properties'
$golandProperties = Join-Path $conf 'GoLand2026.3\idea.properties'
[IO.File]::WriteAllText($riderProperties, "keep.me=1`nidea.mcp.server.force.port=1")
$ownFolder = Join-Path $fakeHome '.agents\skills\goland-go-debug'
New-Item -ItemType Directory -Force -Path $ownFolder, (Join-Path $fakeHome '.claude\skills\my-skill'), $bin | Out-Null
Set-Content -Path (Join-Path $ownFolder 'SKILL.md') -Value 'mine'
Set-Content -Path (Join-Path $bin 'claude.ps1') -Value @"
Add-Content -Path '$log' -Value (`$args -join ' ')
if (`$args[1] -eq 'get') { exit 1 }
exit 0
"@

$saved = @{ USERPROFILE = $env:USERPROFILE; LOCALAPPDATA = $env:LOCALAPPDATA; APPDATA = $env:APPDATA; PATH = $env:PATH; CI = $env:CI }
try {
    $env:USERPROFILE = $fakeHome
    $env:LOCALAPPDATA = Join-Path $fakeHome 'AppData\Local'
    $env:APPDATA = Join-Path $fakeHome 'AppData\Roaming'
    $env:PATH = "$bin;$env:PATH"
    Remove-Item Env:CI -ErrorAction SilentlyContinue

    $skillsOutput = Invoke-JetBrainsScript 'jetbrains-skills'
    foreach ($dir in (Join-Path $fakeHome '.claude\skills'), (Join-Path $fakeHome '.agents\skills')) {
        foreach ($name in 'rider-debugging-code', 'rider-database-connection-management', 'rider-cmake-project-configuration') {
            if (-not (Test-Copy (Join-Path $dir $name))) { Stop-Check "$dir has no marked copy of $name" }
        }
        if (Test-Path (Join-Path $dir 'rider-old-only')) { Stop-Check "$dir has a skill of an old Rider version" }
    }
    if (-not (Test-Copy (Join-Path $fakeHome '.claude\skills\goland-go-debug'))) { Stop-Check 'no GoLand skill copy' }
    if ((Get-Content -Raw (Join-Path $ownFolder 'SKILL.md')).Trim() -ne 'mine') { Stop-Check 'the skills script replaced a real folder' }
    if (Test-Path (Join-Path $ownFolder '.jetbrains-skill')) { Stop-Check 'the skills script marked a real folder' }
    if ($skillsOutput -notmatch 'goland-go-debug is not a JetBrains copy') { Stop-Check 'the skills script did not warn about the real folder' }
    if (-not (Test-Path (Join-Path $fakeHome '.claude\skills\my-skill'))) { Stop-Check 'the skills script removed a real skill folder' }

    Invoke-JetBrainsScript 'jetbrains-ports' | Out-Null
    $riderLines = @(Get-Content -Path $riderProperties)
    if ($riderLines -notcontains 'keep.me=1') { Stop-Check 'the ports script lost another property' }
    if (@($riderLines | Where-Object { $_ -match '^idea\.mcp\.server\.force\.port=' }).Count -ne 1) { Stop-Check 'Rider has more than one port line' }
    if ($riderLines -notcontains 'idea.mcp.server.force.port=64342') { Stop-Check 'Rider did not get port 64342' }
    if (@(Get-Content -Path $golandProperties) -notcontains 'idea.mcp.server.force.port=64343') { Stop-Check 'GoLand did not get port 64343' }
    $before = Get-Content -Raw -Path $riderProperties
    if ((Invoke-JetBrainsScript 'jetbrains-ports').Trim() -or (Get-Content -Raw -Path $riderProperties) -ne $before) {
        Stop-Check 'a second run of the ports script changed a file'
    }

    Invoke-JetBrainsScript 'claude-jetbrains-mcp' | Out-Null
    $calls = @(Get-Content -Path $log)
    foreach ($server in 'jetbrains-rider http://127.0.0.1:64342/stream', 'jetbrains-goland http://127.0.0.1:64343/stream') {
        if ($calls -notcontains "mcp add --scope user --transport http $server") { Stop-Check "Claude Code did not get $server" }
    }

    $servers = & $Chezmoi --config $Config --source $repo execute-template '{{ includeTemplate "agent-mcp-servers" . }}' | ConvertFrom-Json
    if ($servers.'jetbrains-rider' -ne 'http://127.0.0.1:64342/stream' -or $servers.'jetbrains-goland' -ne 'http://127.0.0.1:64343/stream') {
        Stop-Check 'Codex, agy and opencode did not get the JetBrains servers'
    }

    Set-Content -Path (Join-Path $cache "Rider2026.3\$resources\rider.provider\debugging-code\SKILL.md") -Value 'updated'
    Remove-Item -Recurse -Force -Path (Join-Path $cache 'GoLand2026.3')
    Invoke-JetBrainsScript 'jetbrains-skills' | Out-Null
    if (Test-Path (Join-Path $fakeHome '.claude\skills\goland-go-debug')) { Stop-Check 'the skills script kept the copy of a removed IDE' }
    if (-not (Test-Path (Join-Path $ownFolder 'SKILL.md'))) { Stop-Check 'the skills script removed a real folder' }
    if ((Get-Content -Raw (Join-Path $fakeHome '.claude\skills\rider-debugging-code\SKILL.md')).Trim() -ne 'updated') {
        Stop-Check 'the skills script did not refresh a changed skill'
    }
} finally {
    foreach ($name in $saved.Keys) { Set-Item -Path "Env:$name" -Value $saved[$name] -ErrorAction SilentlyContinue }
    if ($null -eq $saved.CI) { Remove-Item Env:CI -ErrorAction SilentlyContinue }
    Remove-Item -Recurse -Force -Path $work -ErrorAction SilentlyContinue
}
Write-Host 'check-jetbrains: Windows skills, ports and MCP servers are right for fake Rider and GoLand'
