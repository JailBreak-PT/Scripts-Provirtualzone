<#
.SYNOPSIS
# =====================================================================================
# Name:      Post-Migration-Toolkit-v3.0.ps1
# Author:    Luciano Patrao
# Version:   3.0
#
# v3.0: Unified script that combines the safe toolkit with the aggressive removal script.
# =====================================================================================
.DESCRIPTION
    A complete and universal toolkit for post-migration cleanup of Windows VMs.
    - Default mode performs a safe cleanup with automatic backups and an enhanced device search.
    - The new -Aggressive mode performs a deeper cleanup, including forced removal of services.
.CHANGELOG
    v3.0 - 19/09/2025:
    - Integrated the "Hidden_Devices_Remove_Total" script into the "PostCutover_Network_Sanity" toolkit.
    - Added a new '-Aggressive' parameter to enable forced removal of VMware services.
    - The device cleanup function was improved to search by Name and Hardware ID (VEN_15AD) in all modes.
#>

#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    # Specific cleanup tasks
    [switch]$CleanupDevices,
    [switch]$RemoveDriverStore,
    [switch]$FlushDns,
    [switch]$WinsockReset,

    # NEW AGGRESSIVE MODE
    [switch]$Aggressive,

    # Restore Mode
    [switch]$Restore,
    [switch]$RestoreIP,
    [string]$BackupPath,

    # Options
    [switch]$NoColor
)

Clear-Host

# 0. Administrator Check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run with Administrator privileges."; exit 1
}

# Get system information
$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
Write-Host "Checking virtualization platform...   Hypervisor = $($computerSystem.Manufacturer)" -ForegroundColor Cyan
Write-Host ""

# --- Platform / Hypervisor Check ---
if ($computerSystem.Manufacturer -like "*VMware*") {
    Write-Warning "This VM is running on VMware. This script should not be run in VMware environments."
    Write-Host ""
    do { $resp1 = (Read-Host "Are you sure you want to continue? (s/n)").ToLower().Trim() } while (-not @('s','n','sim','nao').Contains($resp1))
    if ($resp1.StartsWith('n')) { Write-Host ""; Write-Host "Operation canceled by the user." -ForegroundColor Red; return }
    Write-Host ""
    do { $resp2 = (Read-Host "Confirm again to continue (second confirmation). Continue? (s/n)").ToLower().Trim() } while (-not @('s','n','sim','nao').Contains($resp2))
    if ($resp2.StartsWith('n')) { Write-Host ""; Write-Host "Operation canceled by the user." -ForegroundColor Red; return }
    Write-Host ""
    Write-Host "User confirmed twice. Continuing script execution..." -ForegroundColor Green
} else {
    Write-Host ("[INFO] Hypervisor detected: {0} | Model: {1}. " -f $computerSystem.Manufacturer, $computerSystem.Model) -ForegroundColor Yellow -NoNewline
    Write-Host "Continuing..." -ForegroundColor Green
    Write-Host ""
}

# --- VMware Tools Guard ---
function Get-VMwareToolsUninstallInfo {
    $paths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($p in $paths) {
        Get-ChildItem $p -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue
            if ($props.DisplayName -and $props.DisplayName -like 'VMware Tools*') {
                return [pscustomobject]@{ DisplayName = $props.DisplayName; UninstallString = $props.UninstallString }
            }
        }
    }
    return $null
}
function Prompt-YesNo($question) {
    do { $r = (Read-Host "$question (s/n)").ToLower().Trim() } while ($r -notin @('s','n','sim','nao'))
    return $r.StartsWith('s')
}

$vmtools = Get-VMwareToolsUninstallInfo
if ($vmtools) {
    Write-Warning ("VMware Tools detected: {0}. This script should not run until VMware Tools is removed." -f $vmtools.DisplayName)
    if (Prompt-YesNo "Do you want to attempt an automated uninstall of VMware Tools now and exit") {
        $canProceed = $false
        if ($computerSystem.Manufacturer -like "*VMware*") {
            if (Prompt-YesNo "Since this VM is in a VMware environment, confirm again to uninstall VMware Tools now") {
                $canProceed = $true
            }
        } else {
            $canProceed = $true
        }
        if ($canProceed) {
            'VMTools','VMUSBArbService' | ForEach-Object { try { Stop-Service $_ -Force -ErrorAction SilentlyContinue } catch {} }
            $u = $vmtools.UninstallString
            if ($u -match '(?i)msiexec') { $cmd = 'msiexec.exe'; $args = ($u -replace '/I', '/X' -replace '(?i)msiexec(\.exe)?\s*', '') + ' /qn REBOOT=ReallySuppress' } else { $parts = [System.Text.RegularExpressions.Regex]::Split($u, '\s+', 2); $cmd = $parts[0]; $args = if ($parts.Count -gt 1) { $parts[1] } else { '' }; if ($args -notmatch '(?i)/s|/silent|/qn|quiet') { $args += " /s" }; if ($args -notmatch '(?i)REBOOT=ReallySuppress') { $args += " REBOOT=ReallySuppress" } }
            Write-Host "Attempting standard silent uninstall..." -ForegroundColor Cyan
            try {
                $p = Start-Process -FilePath $cmd -ArgumentList $args -Wait -PassThru -WindowStyle Hidden; $code = $p.ExitCode
                if ($code -eq 0 -or $code -eq 3010) {
                    Write-Host ("Standard uninstall succeeded (exit {0}). A reboot is required. Please reboot, then run this script again." -f $code) -ForegroundColor Green
                } else {
                    Write-Warning ("Standard uninstaller failed with a fatal error (exit code: {0})." -f $code)
                    Write-Host ""
                    Write-Host "The standard uninstall failed. This is common on migrated VMs where the software is corrupted." -ForegroundColor Yellow
                    Write-Host ""
                    Write-Host "Please choose an option:" -ForegroundColor Cyan
                    Write-Host "  [1] Exit script for manual removal"
                    Write-Host "  [2] Attempt automated forceful 'scorched-earth' removal (Last Resort)"
                    Write-Host ""
                    do {
                        $choice = Read-Host "Enter your choice (1 or 2)"
                    } while ($choice -notin @('1', '2'))
                    switch ($choice) {
                        '1' { Write-Host ""; Write-Host "Exiting script. Please remove VMware Tools manually before running again." -ForegroundColor Yellow }
                        '2' { Write-Host ""; if (Prompt-YesNo "CONFIRM: The forceful removal will aggressively delete files, services, and registry keys. This is a last resort. Are you sure?") { Invoke-ForceRemoveVMwareTools } else { Write-Host "Forceful removal canceled by user." -ForegroundColor Red } }
                    }
                }
            } catch {
                Write-Host ("Failed to launch uninstaller: {0}" -f $_.Exception.Message) -ForegroundColor Red
            }
        } else {
            Write-Host "Operation canceled by user." -ForegroundColor Red
        }
    } else {
        Write-Host "Please uninstall VMware Tools manually, reboot, then run this script again." -ForegroundColor Yellow
    }
    return
}
# --- end VMware Tools guard ---

# ------------------- Helper Functions -------------------
function New-PathSafe([string]$Path) { if (-not (Test-Path -LiteralPath $Path)) { $null = New-Item -ItemType Directory -Path $Path -Force } }
$script:UseColor = -not $NoColor; $script:LogRoot  = 'C:\PostMig\Logs'; $script:BackupRoot = 'C:\PostMig\Backups'
function Initialize-Log { New-PathSafe $script:LogRoot; $ts = Get-Date -Format "yyyyMMdd_HHmmss"; $script:LogFile = Join-Path $script:LogRoot ("PostMigrationToolkit_{0}.log" -f $ts) }
function Write-LogLine { param([string]$Message, [string]$Level = "INFO")
    "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message | Out-File -FilePath $script:LogFile -Encoding UTF8 -Append
}
function Out-Msg { param( [ValidateSet('HEADER','ACTION','OK','WARN','ERROR','INFO')][string]$Level = 'INFO', [string]$Message, [int]$Indent = 0)
    $pad = ' ' * ($Indent * 2); $prefix = switch ($Level) { 'HEADER' { '==>' } 'ACTION' { '  >' } 'OK' { '    OK' } 'WARN' { '    WARNING' } 'ERROR'  { '    ERROR' } default  { '    .' } }
    $text = "{0}[{1}] {2}" -f $pad, $prefix, $Message; Write-LogLine -Message $Message -Level $Level
    if ($script:UseColor) { $color = switch ($Level) { 'HEADER' { 'Cyan' } 'ACTION' { 'Cyan' } 'OK' { 'Green' } 'WARN' { 'Yellow' } 'ERROR'  { 'Red' } default  { 'Gray' } }; Write-Host $text -ForegroundColor $color } else { Write-Host $text }
}
function Get-LatestBackupFolder { param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root)) { return $null }; $dirs = Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending; if ($dirs) { return $dirs[0].FullName } else { return $null }
}
function Export-Backups { param([string]$DestRoot)
    $dest = Join-Path $DestRoot (Get-Date -Format "yyyyMMdd_HHmmss"); New-PathSafe $dest; Out-Msg -Level ACTION -Message "Exporting backups to $dest" -Indent 1
    Get-PnpDevice -PresentOnly:$false | Select-Object InstanceId, Class, FriendlyName, Manufacturer, Present, Status | Export-Csv (Join-Path $dest 'DeviceInventory.csv') -NoTypeInformation -Encoding UTF8
    $netSnap = Get-NetIPConfiguration | Select-Object InterfaceAlias, InterfaceIndex, InterfaceDescription, NetProfile.Name, @{n="IPv4";e={$_.IPv4Address.IPAddress}}, @{n="IPv4PrefixLength";e={$_.IPv4Address.PrefixLength}}, @{n="IPv4Gateway";e={$_.IPv4DefaultGateway.NextHop}}, @{n="DNSServers";e={(Get-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4).ServerAddresses -join ","}}, @{n="DHCPEnabled";e={(Get-NetIPInterface -InterfaceIndex $_.InterfaceIndex).Dhcp}}, @{n="MAC";e={(Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue).MacAddress}}
    $netSnap | Export-Csv (Join-Path $dest 'IPConfig.csv') -NoTypeInformation -Encoding UTF8
    return $dest
}
function Restore-Drivers { param([string]$FromPath)
    $drivers = Join-Path $FromPath 'Drivers'; if (-not (Test-Path -LiteralPath $drivers)) { throw "The Drivers folder was not found in the backup: $FromPath" }
    Out-Msg -Level ACTION -Message "Restoring drivers from $drivers" -Indent 1; & pnputil.exe /add-driver "$drivers\*.inf" /subdirs /install | Out-File (Join-Path $FromPath 'RestoreDrivers.txt') -Append; Out-Msg -Level OK -Message "Driver restore completed" -Indent 1
}
function Restore-IPs { param([string]$FromPath)
    $csv = Join-Path $FromPath 'IPConfig.csv'; if (-not (Test-Path -LiteralPath $csv)) { throw "IPConfig.csv was not found in the backup: $FromPath" }
    Out-Msg -Level ACTION -Message "Restoring IP configurations from $csv" -Indent 1
    $snap = Import-Csv $csv
    foreach ($i in $snap) {
        $nic = $null
        if ($i.MAC) { $nic = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.MacAddress -eq $i.MAC } | Select-Object -First 1 }
        if (-not $nic -and $i.InterfaceAlias) { $nic = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $i.InterfaceAlias } | Select-Object -First 1 }
        if (-not $nic) { Out-Msg -Level WARN -Message ("Skipping: could not map saved interface for {0}" -f $i.InterfaceAlias) -Indent 2; continue }
        if ($PSCmdlet.ShouldProcess($nic.Name, "Apply saved IP/DNS")) {
            try {
                if ($i.DHCPEnabled -eq "Enabled") {
                    Set-NetIPInterface -InterfaceAlias $nic.Name -Dhcp Enabled -ErrorAction SilentlyContinue
                    Set-DnsClientServerAddress -InterfaceAlias $nic.Name -ResetServerAddresses -ErrorAction SilentlyContinue
                } else {
                    Get-NetIPAddress -InterfaceAlias $nic.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.PrefixOrigin -ne "WellKnown" } | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
                    if ($i.IPv4) { New-NetIPAddress -InterfaceAlias $nic.Name -IPAddress $i.IPv4 -PrefixLength $i.IPv4PrefixLength -DefaultGateway $i.IPv4Gateway -ErrorAction SilentlyContinue }
                    if ($i.DNSServers) { $dns = $i.DNSServers -split ","; Set-DnsClientServerAddress -InterfaceAlias $nic.Name -ServerAddresses $dns -ErrorAction SilentlyContinue }
                }
                Out-Msg -Level OK -Message ("IP applied to {0}" -f $nic.Name) -Indent 2
            } catch { Out-Msg -Level WARN -Message ("Failed to apply IP to {0}: {1}" -f $nic.Name, $_.Exception.Message) -Indent 2 }
        }
    }
}

# ==========================================================
# ============ UPDATED CLEANUP FUNCTIONS =============
# ==========================================================
function Remove-VmwareServices-Aggressive {
    Out-Msg -Level ACTION -Message "Aggressively removing VMware services (-Aggressive)..." -Indent 1
    $vmwareServices = @('VMTools', 'VGAuthService', 'VMware Physical Disk Helper Service', 'VMUSBArbService')
    foreach ($service in $vmwareServices) {
        Out-Msg -Level INFO -Message "Stopping and deleting service: $service" -Indent 2
        Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
        $serviceObject = Get-Service -Name $service -ErrorAction SilentlyContinue
        if ($serviceObject) {
            sc.exe delete $service | Out-Null
        }
    }
    Write-Host ""
}
function Cleanup-AllVmwareDevices-Enhanced {
    Out-Msg -Level ACTION -Message "Starting comprehensive device cleanup..." -Indent 1
    $vmwareDevicePatterns = @( "*VMware*", "vmxnet3*", "Intel(R) 82574L*" )
    $devicesFoundByName = @()
    foreach ($pattern in $vmwareDevicePatterns) {
        $found = Get-PnpDevice -FriendlyName $pattern -ErrorAction SilentlyContinue
        if ($found) { $devicesFoundByName += $found }
    }
    $devicesFoundByHid = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { ($_.HardwareID -like "*VEN_15AD*") }
    $allFoundDevices = $devicesFoundByName + $devicesFoundByHid
    $devicesToRemove = $allFoundDevices | Where-Object { -not $_.Present } | Sort-Object -Property InstanceId -Unique
    if ($devicesToRemove) {
        Out-Msg -Level WARN -Message "The following $($devicesToRemove.Count) hidden VMware devices were found:" -Indent 1
        $devicesToRemove | Format-Table @{N='Name';E={$_.FriendlyName}}, Class, Status, InstanceId -AutoSize
        if ($PSCmdlet.ShouldProcess("the $($devicesToRemove.Count) devices listed above", "Remove with pnputil.exe")) {
            Read-Host "Press ENTER to continue with the removal..."
            foreach ($device in $devicesToRemove) {
                Out-Msg -Level ACTION -Message "Removing device: '$($device.FriendlyName)'..." -Indent 2
                $proc = Start-Process -FilePath "pnputil.exe" -ArgumentList "/remove-device `"$($device.InstanceId)`" /subtree /force" -Wait -PassThru -WindowStyle Hidden
                if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                    Out-Msg -Level OK -Message "Successfully removed." -Indent 3
                } else {
                    Out-Msg -Level ERROR -Message "Failed to remove the device. Exit Code: $($proc.ExitCode)" -Indent 3
                }
            }
        }
    } else {
        Out-Msg -Level OK -Message "No hidden VMware devices were found." -Indent 1
    }
    Write-Host ""
}
function Cleanup-DriverStoreVmware {
    Out-Msg -Level ACTION -Message "Enumerating DriverStore for VMware-named drivers" -Indent 1
    $oemSet = @(); $current = @{};
    & pnputil.exe /enum-drivers | ForEach-Object {
        if ($_ -match 'Published Name\s*:\s*(oem\d+\.inf)') { $current['Name'] = $Matches[1] }
        elseif ($_ -match 'Provider Name\s*:\s*(.*)') { $current['Provider'] = $Matches[1].Trim() }
        elseif ($_ -match 'Driver Name\s*:\s*(.*)') { $current['Driver'] = $Matches[1].Trim(); if ($current['Name']) { $oemSet += [pscustomobject]$current; $current = @{} } }
    }
    $vmwOems = $oemSet | Where-Object { $_.Provider -match 'VMware' -or $_.Driver -match 'vmxnet|pvscsi|vmci|vmmouse|svga' }
    if (-not $vmwOems) { Out-Msg -Level INFO -Message "No VMware-named driver packages found." -Indent 2; Write-Host ""; return }
    Out-Msg -Level WARN -Message "The following driver packages will be removed:" -Indent 1
    $vmwOems | Select-Object Name, Provider, Driver | Format-Table -AutoSize
    if ($PSCmdlet.ShouldProcess("the $($vmwOems.Count) listed driver packages", "Delete from DriverStore with pnputil.exe")) {
        foreach ($oem in $vmwOems) {
            Out-Msg -Level ACTION -Message "Deleting package: '{0}' ({1})..." -f $oem.Name, $oem.Driver -Indent 2
            & pnputil.exe /delete-driver $oem.Name /uninstall /force | Out-Null
            if ($LASTEXITCODE -eq 0) { Out-Msg -Level OK -Message "Successfully removed." -Indent 3 } else { Out-Msg -Level ERROR -Message "FAILED with exit code $($LASTEXITCODE) for $($oem.Name)" -Indent 3 }
        }
    }
    Write-Host ""
}
function Do-FlushDns { 
    Out-Msg -Level ACTION -Message "Flushing DNS cache" -Indent 1; 
    & ipconfig.exe /flushdns | Out-Null
    Out-Msg -Level OK -Message "DNS cache flushed" -Indent 2; 
    Write-Host "" 
}
function Do-WinsockReset { 
    Out-Msg -Level ACTION -Message "Requesting Winsock reset" -Indent 1; 
    & netsh.exe winsock reset | Out-Null
    Out-Msg -Level WARN -Message "A reboot is recommended after a Winsock reset" -Indent 2; 
    Write-Host "" 
}
function Invoke-AllCleanupTasks {
    Out-Msg -Level HEADER -Message "Running all cleanup tasks (default mode)"
    if ($Aggressive) {
        Remove-VmwareServices-Aggressive
    }
    Cleanup-AllVmwareDevices-Enhanced
    Cleanup-DriverStoreVmware
    Do-FlushDns
    Do-WinsockReset
}
function Test-IsCleanupNeeded {
    $ghostNics = Get-PnpDevice -PresentOnly:$false -ErrorAction SilentlyContinue | Where-Object { $_.Class -eq 'Net' -and -not $_.Present -and ($_.FriendlyName -match 'VMware|vmxnet') }
    $hiddenDevices = Get-PnpDevice -PresentOnly:$false -ErrorAction SilentlyContinue | Where-Object { $_.Class -ne 'Net' -and -not $_.Present -and ($_.Manufacturer -match 'VMware' -or $_.FriendlyName -match 'VMware|pvscsi|vmci|vmmouse|svga') }
    return ($ghostNics.Count -gt 0) -or ($hiddenDevices.Count -gt 0)
}

# ------------------- Main Logic -------------------
Initialize-Log
Out-Msg -Level HEADER -Message "Starting Post-Migration-Toolkit-v3.0.ps1"
Write-Host ""
if ($Restore) {
    $src = $BackupPath
    if (-not $src -or -not (Test-Path -LiteralPath $src)) {
        $src = Get-LatestBackupFolder -Root $script:BackupRoot
        if (-not $src) { throw "No backup found in $($script:BackupRoot)" }
        Out-Msg -Level INFO -Message "Using latest backup: $src" -Indent 1
    } else {
        Out-Msg -Level INFO -Message "Using provided backup path: $src" -Indent 1
    }
    Restore-Drivers -FromPath $src
    if ($RestoreIP) {
        Restore-IPs -FromPath $src
    }
    Out-Msg -Level OK -Message "Restore complete" -Indent 1
    return
}

# Pre-check logic
$commonParams = 'WhatIf','Confirm','Verbose','Debug','ErrorAction','ErrorVariable','OutVariable','OutBuffer','PipelineVariable','WarningAction','WarningVariable','Aggressive'
$deviceCleanupIntended = $CleanupDevices -or $RemoveDriverStore
if (-not ($PSBoundParameters.Keys | Where-Object { $commonParams -notcontains $_ })) { $deviceCleanupIntended = $true }
if ($deviceCleanupIntended) {
    if (-not (Test-IsCleanupNeeded)) { 
        Out-Msg -Level OK -Message "Pre-check found no VMware artifacts. System is clean. Exiting."
        Write-Host ""
        return 
    } else { 
        Out-Msg -Level OK -Message "Pre-check complete. VMware artifacts found, proceeding with cleanup." -Indent 1 
    }
    Write-Host ""
}

# Backup phase
try {
    $script:CurrentBackup = Export-Backups -DestRoot $script:BackupRoot
} catch {
    Out-Msg -Level ERROR -Message ("Backup creation failed: {0}" -f $_.Exception.Message) -Indent 1; return
}

# Determine which tasks to run
$runAll = -not ($PSBoundParameters.Keys | Where-Object { $commonParams -notcontains $_ })
if ($runAll) {
    Invoke-AllCleanupTasks
} else {
    Out-Msg -Level HEADER -Message "Running in specific task mode"
    if ($Aggressive)         { Remove-VmwareServices-Aggressive }
    if ($CleanupDevices)     { Cleanup-AllVmwareDevices-Enhanced }
    if ($RemoveDriverStore)  { Cleanup-DriverStoreVmware }
    if ($FlushDns)           { Do-FlushDns }
    if ($WinsockReset)       { Do-WinsockReset }
}

Write-Host ""
Out-Msg -Level ACTION -Message "Re-scanning devices (pnputil /scan-devices)" -Indent 1
& pnputil.exe /scan-devices | Out-Null
Write-Host ""
Out-Msg -Level OK -Message "Completed. Log: $script:LogFile  Backups: $script:CurrentBackup"