[CmdletBinding()]
param([switch] $ScanOnly)

$ErrorActionPreference = 'Continue'

function Get-OperationResultName {
    param([int] $ResultCode)
    switch ($ResultCode) {
        0 { 'Not started' }
        1 { 'In progress' }
        2 { 'Succeeded' }
        3 { 'Succeeded with errors' }
        4 { 'Failed' }
        5 { 'Aborted' }
        default { "Unknown ($ResultCode)" }
    }
}

if (-not $ScanOnly -and (Get-Command Update-MpSignature -ErrorAction SilentlyContinue)) {
    Write-Host ''
    Write-Host '==> Microsoft Defender signatures'
    try {
        Update-MpSignature
        Write-Host 'Defender signatures are current.'
    }
    catch { Write-Warning "Defender signature update failed: $($_.Exception.Message)" }
}

Write-Host ''
Write-Host '==> Windows Update'
try {
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSession.ClientApplicationID = 'PowerShell update-all'
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $searchResult = $updateSearcher.Search('IsInstalled=0 and IsHidden=0 and IsAssigned=1')
    $selectedUpdates = New-Object -ComObject Microsoft.Update.UpdateColl

    for ($index = 0; $index -lt $searchResult.Updates.Count; $index++) {
        $update = $searchResult.Updates.Item($index)
        try {
            if (-not $update.EulaAccepted) { $update.AcceptEula() }
            [void]$selectedUpdates.Add($update)
            Write-Host "  $($update.Title)"
        }
        catch { Write-Warning "Skipping '$($update.Title)': $($_.Exception.Message)" }
    }

    if ($selectedUpdates.Count -eq 0) {
        Write-Host 'No assigned Windows updates are available.'
    }
    elseif ($ScanOnly) {
        Write-Host "$($selectedUpdates.Count) assigned Windows update(s) found."
    }
    else {
        $updateDownloader = $updateSession.CreateUpdateDownloader()
        $updateDownloader.Updates = $selectedUpdates
        $downloadResult = $updateDownloader.Download()
        Write-Host "Download result: $(Get-OperationResultName $downloadResult.ResultCode)"

        $downloadedUpdates = New-Object -ComObject Microsoft.Update.UpdateColl
        for ($index = 0; $index -lt $selectedUpdates.Count; $index++) {
            $update = $selectedUpdates.Item($index)
            if ($update.IsDownloaded) { [void]$downloadedUpdates.Add($update) }
            else { Write-Warning "Not downloaded: $($update.Title)" }
        }

        if ($downloadedUpdates.Count -gt 0) {
            $updateInstaller = $updateSession.CreateUpdateInstaller()
            $updateInstaller.Updates = $downloadedUpdates
            $updateInstaller.AllowSourcePrompts = $false
            $installResult = $updateInstaller.Install()
            Write-Host "Install result: $(Get-OperationResultName $installResult.ResultCode)"
            if ($installResult.RebootRequired) { Write-Warning 'Windows Update requires a reboot.' }
        }
    }
}
catch { Write-Warning "Windows Update failed: $($_.Exception.Message)" }

$dellCommandUpdate = 'C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe'
if (Test-Path -LiteralPath $dellCommandUpdate) {
    Write-Host ''
    Write-Host '==> Dell Command Update'
    $dellService = Get-Service -Name 'DellClientManagementService' -ErrorAction SilentlyContinue
    if ($dellService -and $dellService.Status -ne 'Running') {
        try {
            Start-Service -InputObject $dellService -WarningAction SilentlyContinue
            $dellService.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
        }
        catch { Write-Warning "Could not start Dell Client Management Service: $($_.Exception.Message)" }
    }

    $dellExitCode = $null
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        if ($ScanOnly) { & $dellCommandUpdate /scan -silent }
        else { & $dellCommandUpdate /applyUpdates -silent -reboot=disable -autoSuspendBitLocker=enable }
        $dellExitCode = $LASTEXITCODE
        Write-Host ''
        if ($dellExitCode -ne 3003 -or $attempt -eq 4) { break }
        Write-Host "Dell service is busy (code $dellExitCode); retrying in 10 seconds..."
        Start-Sleep -Seconds 10
    }

    switch ($dellExitCode) {
        0 { Write-Host 'Dell Command Update completed successfully.' }
        1 { Write-Warning 'Dell updates were installed and require a reboot.' }
        5 { Write-Warning 'Dell Command Update is waiting for a pending reboot.' }
        500 { Write-Host 'No Dell updates are available.' }
        3003 { Write-Warning 'Dell Client Management Service remained busy after four attempts.' }
        3004 { Write-Host 'Dell Command Update is updating itself in the background.' }
        3005 { Write-Host 'Dell Client Management Service is already installing pending updates.' }
        default { Write-Warning "Dell Command Update exited with code $dellExitCode." }
    }
}

if (-not $ScanOnly) {
    Write-Host ''
    Write-Host '==> Microsoft Store apps'
    try {
        $storeManager = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName 'MDM_EnterpriseModernAppManagement_AppManagement01' -ErrorAction Stop
        $storeResult = Invoke-CimMethod -InputObject $storeManager -MethodName UpdateScanMethod -ErrorAction Stop
        if ($storeResult.ReturnValue -eq 0) { Write-Host 'Microsoft Store update scan started.' }
        else { Write-Warning "Microsoft Store update scan returned $($storeResult.ReturnValue)." }
    }
    catch { Write-Warning "Microsoft Store update scan failed: $($_.Exception.Message)" }
}
