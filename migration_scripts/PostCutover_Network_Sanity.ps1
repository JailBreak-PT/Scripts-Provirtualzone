# =====================================================================================
# Name: PostCutover_Network_Sanity_v2.2.ps1
# Created: 2025-08-31
# Author: Luciano Patrao (with colorized output and built-in restore)
#
# --- CHANGE LOG ---
# v2.2: Integrated user-provided, field-tested device removal logic.
#       - Replaced the two separate device removal functions with a single,
#         more effective function using the user's search patterns.
#       - Replaced -CleanupNics and -CleanupHiddenDevices with a single
#         -CleanupDevices parameter to match the new unified logic.
#
# --- USAGE (Run as Administrator) ---
#
#   .\PostCutover_Network_Sanity.ps1                          # RUNS ALL CLEANUP TASKS (Default Action)
#
#   --- To run ONLY a specific task ---
#   .\PostCutover_Network_Sanity.ps1 -CleanupDevices          # Removes ALL non-present VMware devices
#   .\PostCutover_Network_Sanity.ps1 -RemoveDriverStore       # Deletes ONLY VMware-named DriverStore packages
#   .\PostCutover_Network_Sanity.ps1 -FlushDns                # Flushes ONLY the DNS cache
#   .\PostCutover_Network_Sanity.ps1 -WinsockReset            # Resets ONLY Winsock
#
#   --- Restore functionality (unchanged) ---
#   .\PostCutover_Network_Sanity.ps1 -Restore                 # Restore drivers from latest backup and exit
#   .\PostCutover_Network_Sanity.ps1 -Restore -RestoreIP      # Restore drivers and reapply saved IPs
#
# =====================================================================================

#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    # Specific cleanup tasks - MODIFIED
    [switch]$CleanupDevices,
    [switch]$RemoveDriverStore,
    [switch]$FlushDns,
    [switch]$WinsockReset,

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

# --- Platform / Hypervisor check ---
if ($computerSystem.Manufacturer -like "*VMware*") {
    Write-Warning "This VM is running on VMware. This script should not be executed on VMware environments."
    Write-Host ""
    do { $resp1 = (Read-Host "Are you sure you want to continue? (y/n)").ToLower().Trim() } while (-not @('y','n','yes','no').Contains($resp1))
    if ($resp1.StartsWith('n')) { Write-Host ""; Write-Host "Operation canceled by user." -ForegroundColor Red; return }
    Write-Host ""
    do { $resp2 = (Read-Host "Confirm again to continue (second confirmation). Continue? (y/n)").ToLower().Trim() } while (-not @('y','n','yes','no').Contains($resp2))
    if ($resp2.StartsWith('n')) { Write-Host ""; Write-Host "Operation canceled by user." -ForegroundColor Red; return }
    Write-Host ""
    Write-Host "User confirmed twice. Continuing script execution..." -ForegroundColor Green
} else {
    Write-Host ("[INFO] Detected hypervisor: {0} | Model: {1}. " -f $computerSystem.Manufacturer, $computerSystem.Model) -ForegroundColor Yellow -NoNewline
    Write-Host "Continuing..." -ForegroundColor Green
    Write-Host ""
}

# --- VMware Tools guard ---
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
    do { $r = (Read-Host "$question (y/n)").ToLower().Trim() } while ($r -notin @('y','n','yes','no'))
    return -not $r.StartsWith('n')
}
function Invoke-ForceRemoveVMwareTools {
    Write-Host "`n===========================================================" -ForegroundColor Red
    Write-Host "Starting Forceful 'Scorched-Earth' Removal of VMware Tools" -ForegroundColor Yellow
    Write-Host "===========================================================" -ForegroundColor Red
    Write-Host "`n--- Step 1: Stopping and Deleting VMware Services ---" -ForegroundColor Cyan
    $vmwareServices = @('VMTools', 'VGAuthService', 'VMware Physical Disk Helper Service', 'VMUSBArbService', 'VMwareCAFManagementAgentHost')
    foreach ($service in $vmwareServices) { Write-Host " > Targeting service: $service"; Stop-Service -Name $service -Force -ErrorAction SilentlyContinue; $serviceObject = Get-Service -Name $service -ErrorAction SilentlyContinue; if ($serviceObject) { Write-Host "   - Deleting service..."; sc.exe delete $service | Out-Null } }
    Write-Host "`n--- Step 2: Terminating VMware Processes ---" -ForegroundColor Cyan
    'vmtoolsd', 'vmacthlp', 'VGAuthService' | ForEach-Object { Write-Host " > Terminating process: $_"; Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }
    Write-Host "`n--- Step 3: Purging VMware Drivers ---" -ForegroundColor Cyan
    $oemSet = @(); $current = @{}; & pnputil.exe /enum-drivers | ForEach-Object { if ($_ -match 'Published Name\s*:\s*(oem\d+\.inf)') { $current['Name'] = $Matches[1] } elseif ($_ -match 'Provider Name\s*:\s*(.*)') { $current['Provider'] = $Matches[1].Trim() } elseif ($_ -match 'Driver Name\s*:\s*(.*)') { $current['Driver'] = $Matches[1].Trim(); if ($current['Name']) { $oemSet += [pscustomobject]$current; $current = @{} } } }
    $vmwOems = $oemSet | Where-Object { $_.Provider -match 'VMware' }; if ($vmwOems) { foreach ($oem in $vmwOems) { Write-Host " > Deleting driver package: $($oem.Name) ($($oem.Driver))"; pnputil.exe /delete-driver $oem.Name /uninstall /force | Out-Null } } else { Write-Host " > No VMware driver packages found." }
    Write-Host "`n--- Step 4: Deleting VMware Tools Files and Folders ---" -ForegroundColor Cyan
    @("$env:ProgramFiles\VMware\VMware Tools", "$env:ProgramData\VMware\VMware Tools") | ForEach-Object { if (Test-Path $_) { Write-Host " > Deleting path: $_"; Remove-Item -Path $_ -Recurse -Force -ErrorAction SilentlyContinue } }
    Write-Host "`n--- Step 5: Scrubbing Registry ---" -ForegroundColor Cyan
    $registryPaths = @('HKLM:\SOFTWARE\VMware, Inc.\VMware Tools', 'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMware Tools')
    $uninstallKey = Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue | ForEach-Object { $displayName = Get-ItemProperty -Path $_.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty "DisplayName"; if ($displayName -like "VMware Tools*") { return $_.PSPath } }; if ($uninstallKey) { $registryPaths += $uninstallKey }
    foreach ($regPath in $registryPaths) { if (Test-Path $regPath) { Write-Host " > Deleting registry key: $regPath"; Remove-Item -Path $regPath -Recurse -Force -ErrorAction SilentlyContinue } }
    Write-Host "`n======================= COMPLETE =======================" -ForegroundColor Green
    Write-Host "Forceful removal attempt finished."
    Write-Host "A SYSTEM REBOOT IS REQUIRED to complete the process." -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Green
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

# ------------------- Helpers -------------------
function New-PathSafe([string]$Path) { if (-not (Test-Path -LiteralPath $Path)) { $null = New-Item -ItemType Directory -Path $Path -Force } }
$script:UseColor = -not $NoColor; $script:LogRoot  = 'C:\PostMig\Logs'; $script:BackupRoot = 'C:\PostMig\Backups'
function Initialize-Log { New-PathSafe $script:LogRoot; $ts = Get-Date -Format "yyyyMMdd_HHmmss"; $script:LogFile = Join-Path $script:LogRoot ("PostCutover_Network_Sanity_{0}.log" -f $ts) }
function Write-LogLine { param([string]$Message, [string]$Level = "INFO")
    "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message | Out-File -FilePath $script:LogFile -Encoding UTF8 -Append
}
function Out-Msg { param( [ValidateSet('HEADER','ACTION','OK','WARN','ERROR','INFO')][string]$Level = 'INFO', [string]$Message, [int]$Indent = 0)
    $pad = ' ' * ($Indent * 2); $prefix = switch ($Level) { 'HEADER' { '==>' } 'ACTION' { '  >' } 'OK' { '    OK' } 'WARN' { '    WARN' } 'ERROR'  { '    ERR' } default  { '    .' } }
    $text = "{0}[{1}] {2}" -f $pad, $prefix, $Message; Write-LogLine -Message $Message -Level $Level
    if ($script:UseColor) { $color = switch ($Level) { 'HEADER' { 'Cyan' } 'ACTION' { 'Cyan' } 'OK' { 'Green' } 'WARN' { 'Yellow' } 'ERROR'  { 'Red' } default  { 'Gray' } }; Write-Host $text -ForegroundColor $color } else { Write-Host $text }
}
function Get-LatestBackupFolder { param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root)) { return $null }; $dirs = Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending; if ($dirs) { return $dirs[0].FullName } else { return $null }
}
function Export-Backups { param([string]$DestRoot)
    $dest = Join-Path $DestRoot (Get-Date -Format "yyyyMMdd_HHmmss"); New-PathSafe $dest; Out-Msg -Level ACTION -Message "Exporting backups to $dest" -Indent 1
    Get-PnpDevice -PresentOnly:$false | Select-Object InstanceId, Class, FriendlyName, Manufacturer, Present, Status | Export-Csv (Join-Path $dest 'DeviceInventory.csv') -NoTypeInformation -Encoding UTF8
    return $dest
}

# ==========================================================
# ============ NEW UNIFIED DEVICE REMOVAL FUNCTION ===========
# ==========================================================
function Cleanup-AllVmwareDevices {
    # 1. Define the patterns of VMware device names to search for
    $vmwareDevicePatterns = @(
        "*VMware*",              # Catches most devices (SVGA, SCSI, etc.)
        "vmxnet3*",              # Catches the VMXNET3 network adapter
        "Intel(R) 82574L*"       # Catches the E1000 network adapter commonly emulated by VMware
    )

    Write-Host "`n[STEP 1/3] Searching for old VMware devices..." -ForegroundColor Cyan

    # 2. Find all devices (including hidden ones) that match the patterns
    $devicesToRemove = @()
    foreach ($pattern in $vmwareDevicePatterns) {
        # Add the found devices to the list, avoiding duplicates
        $found = Get-PnpDevice -FriendlyName $pattern -ErrorAction SilentlyContinue
        if ($found) {
            $devicesToRemove += $found
        }
    }
    # We only care about devices that are no longer present
    $devicesToRemove = $devicesToRemove | Where-Object { -not $_.Present } | Sort-Object -Property InstanceId -Unique

    # 3. Remove the found devices
    if ($devicesToRemove) {
        Write-Host "`n[STEP 2/3] The following VMware devices were found and will be removed:" -ForegroundColor Yellow
        $devicesToRemove | Format-Table @{N='Name';E={$_.FriendlyName}}, Class, Status, InstanceId -AutoSize
        
        if ($PSCmdlet.ShouldProcess("the $($devicesToRemove.Count) devices listed above", "Remove with pnputil.exe")) {
            Read-Host "Press Enter to continue with removal..."

            foreach ($device in $devicesToRemove) {
                Write-Host "Removing device: '$($device.FriendlyName)'..."
                # Use Start-Process for more controlled execution of pnputil.exe
                $proc = Start-Process -FilePath "pnputil.exe" -ArgumentList "/remove-device `"$($device.InstanceId)`" /subtree /force" -Wait -PassThru -WindowStyle Hidden
                
                if ($proc.ExitCode -eq 0) {
                    Write-Host "  > Removed successfully." -ForegroundColor Green
                } else {
                    # Exit code 3010 means a reboot is required, which is a success.
                    if ($proc.ExitCode -eq 3010) {
                        Write-Host "  > Removed successfully. (Reboot pending)" -ForegroundColor Green
                    } else {
                        Write-Warning "  > Failed to remove device. Exit Code: $($proc.ExitCode)"
                    }
                }
            }
        } else {
            Out-Msg -Level INFO -Message "WhatIf: Skipping removal of $($devicesToRemove.Count) devices."
        }
    } else {
        Write-Host "`n[INFO] No old VMware devices were found." -ForegroundColor Green
    }
}
# ==========================================================

function Cleanup-DriverStoreVmware {
    Out-Msg -Level ACTION -Message "Enumerating DriverStore for VMware-named drivers" -Indent 1
    $oemSet = @(); $current = @{};
    & pnputil.exe /enum-drivers | ForEach-Object {
        if ($_ -match 'Published Name\s*:\s*(oem\d+\.inf)') { $current['Name'] = $Matches[1] }
        elseif ($_ -match 'Provider Name\s*:\s*(.*)') { $current['Provider'] = $Matches[1].Trim() }
        elseif ($_ -match 'Driver Name\s*:\s*(.*)') { $current['Driver'] = $Matches[1].Trim(); if ($current['Name']) { $oemSet += [pscustomobject]$current; $current = @{} } }
    }
    $vmwOems = $oemSet | Where-Object { $_.Provider -match 'VMware' -or $_.Driver -match 'vmxnet|pvscsi|vmci|vmmouse|svga' }
    if (-not $vmwOems) { Out-Msg -Level INFO -Message "No VMware-named DriverStore packages found." -Indent 2; Write-Host ""; return }
    Write-Host ""
    Write-Host "[STEP 3/3] The following VMware driver packages will be removed:" -ForegroundColor Cyan
    Write-Host ""
    $vmwOems | Select-Object Name, Provider, Driver | Format-Table
    if ($PSCmdlet.ShouldProcess("the $($vmwOems.Count) driver packages listed above", "Delete from DriverStore with pnputil.exe")) {
        Read-Host "Press Enter to continue with removal..." | Out-Null
        Write-Host ""
        foreach ($oem in $vmwOems) {
            Write-Host ("Removing driver package: '{0}' ({1})..." -f $oem.Name, $oem.Driver)
            & pnputil.exe /delete-driver $oem.Name /uninstall /force | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Host " > Removed successfully." -ForegroundColor Green } else { Write-Warning ("> FAILED with exit code $($LASTEXITCODE) for $($oem.Name)") }
        }
    } else { Out-Msg -Level INFO -Message "WhatIf: Skipping removal of $($vmwOems.Count) driver packages." -Indent 2 }
    Write-Host ""
}
function Do-FlushDns { Out-Msg -Level ACTION -Message "Flushing DNS cache" -Indent 1; & ipconfig.exe /flushdns | Out-File (Join-Path $script:CurrentBackup 'DnsFlush.txt') -Append; Out-Msg -Level OK -Message "DNS cache flushed" -Indent 2; Write-Host "" }
function Do-WinsockReset { Out-Msg -Level ACTION -Message "Winsock reset requested" -Indent 1; & netsh.exe winsock reset | Out-File (Join-Path $script:CurrentBackup 'WinsockReset.txt') -Append; Out-Msg -Level WARN -Message "A reboot is recommended after a Winsock reset" -Indent 2; Write-Host "" }
function Invoke-AllCleanupTasks {
    Cleanup-AllVmwareDevices
    Cleanup-DriverStoreVmware
    Do-FlushDns
    Do-WinsockReset
}
function Restore-Drivers { param([string]$FromPath); $drivers = Join-Path $FromPath 'Drivers'; if (-not (Test-Path -LiteralPath $drivers)) { throw "Drivers folder not found in backup: $FromPath" }; Out-Msg -Level ACTION -Message "Restoring drivers from $drivers" -Indent 1; & pnputil.exe /add-driver "$drivers\*.inf" /subdirs /install | Out-File (Join-Path $FromPath 'RestoreDrivers.txt') -Append; Out-Msg -Level OK -Message "Driver restore completed" -Indent 1 }
function Restore-IPs { param([string]$FromPath); $json = Join-Path $FromPath 'IPConfig.json'; if (-not (Test-Path -LiteralPath $json)) { throw "IPConfig.json not found in backup: $FromPath" }; Out-Msg -Level ACTION -Message "Restoring IP settings from $json" -Indent 1; $snap = Get-Content $json -Raw | ConvertFrom-Json; foreach ($i in $snap) { $nic = $null; if ($i.MAC) { $nic = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.MacAddress -eq $i.MAC } | Select-Object -First 1 }; if (-not $nic -and $i.InterfaceAlias) { $nic = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $i.InterfaceAlias } | Select-Object -First 1 }; if (-not $nic) { Out-Msg -Level WARN -Message ("Skip: could not map saved interface for {0}" -f $i.InterfaceAlias) -Indent 2; continue }; if ($PSCmdlet.ShouldProcess($nic.Name, "Apply saved IP/DNS")) { try { if ($i.DHCPEnabled -eq "Enabled") { Set-NetIPInterface -InterfaceAlias $nic.Name -Dhcp Enabled -ErrorAction SilentlyContinue; Set-DnsClientServerAddress -InterfaceAlias $nic.Name -ResetServerAddresses -ErrorAction SilentlyContinue } else { Get-NetIPAddress -InterfaceAlias $nic.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.PrefixOrigin -ne "WellKnown" } | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue; if ($i.IPv4) { New-NetIPAddress -InterfaceAlias $nic.Name -IPAddress $i.IPv4 -PrefixLength $i.IPv4PrefixLength -DefaultGateway $i.IPv4Gateway -ErrorAction SilentlyContinue }; if ($i.DNSServers) { $dns = $i.DNSServers -split ","; Set-DnsClientServerAddress -InterfaceAlias $nic.Name -ServerAddresses $dns -ErrorAction SilentlyContinue } }; Out-Msg -Level OK -Message ("Applied IP to {0}" -f $nic.Name) -Indent 2 } catch { Out-Msg -Level WARN -Message ("Failed to apply IP to {0}: {1}" -f $nic.Name, $_.Exception.Message) -Indent 2 } } else { Out-Msg -Level INFO -Message ("WhatIf: would apply IP to {0}" -f $nic.Name) -Indent 2 } } }
function Test-IsCleanupNeeded {
    $vmwareDevicePatterns = @("*VMware*", "vmxnet3*", "Intel(R) 82574L*")
    $devicesFound = $false
    foreach ($pattern in $vmwareDevicePatterns) {
        if (Get-PnpDevice -FriendlyName $pattern -ErrorAction SilentlyContinue | Where-Object { -not $_.Present }) {
            $devicesFound = $true
            break
        }
    }
    return $devicesFound # This can be expanded later to check DriverStore too.
}

# ------------------- Main -------------------
Initialize-Log
Out-Msg -Level HEADER -Message "PostCutover_Network_Sanity.ps1 starting"
Write-Host ""
if ($Restore) {
    $src = $BackupPath; if (-not $src -or -not (Test-Path -LiteralPath $src)) { $src = Get-LatestBackupFolder -Root $script:BackupRoot; if (-not $src) { throw "No backups found in $($script:BackupRoot)" }; Out-Msg -Level INFO -Message "Using latest backup: $src" -Indent 1 } else { Out-Msg -Level INFO -Message "Using provided backup path: $src" -Indent 1 }; Restore-Drivers -FromPath $src; if ($RestoreIP) { Restore-IPs -FromPath $src }; Out-Msg -Level OK -Message "Restore complete" -Indent 1; return
}

# Pre-scan logic
$commonParams = 'WhatIf','Confirm','Verbose','Debug','ErrorAction','ErrorVariable','OutVariable','OutBuffer','PipelineVariable','WarningAction','WarningVariable'
$deviceCleanupIntended = $CleanupDevices -or $RemoveDriverStore
if (-not ($PSBoundParameters.Keys | Where-Object { $commonParams -notcontains $_ })) { $deviceCleanupIntended = $true }
if ($deviceCleanupIntended) {
    if (-not (Test-IsCleanupNeeded)) { Out-Msg -Level INFO -Message "Pre-scan found no VMware devices or drivers to remove." -Indent 1; Out-Msg -Level OK -Message "System is already clean. No action required. Exiting."; Write-Host ""; return } else { Out-Msg -Level OK -Message "Pre-scan complete. VMware artifacts found, proceeding with cleanup." -Indent 1 }
    Write-Host ""
}

try {
    $script:CurrentBackup = Export-Backups -DestRoot $script:BackupRoot
} catch {
    Out-Msg -Level ERROR -Message ("Backup failed: {0}" -f $_.Exception.Message) -Indent 1; return
}

# MODIFIED main logic
$runAll = -not ($PSBoundParameters.Keys | Where-Object { $commonParams -notcontains $_ })
if ($runAll) {
    Invoke-AllCleanupTasks
} else {
    Out-Msg -Level HEADER -Message "Running in specific task mode"
    if ($CleanupDevices)      { Cleanup-AllVmwareDevices }
    if ($RemoveDriverStore)   { Cleanup-DriverStoreVmware }
    if ($FlushDns)            { Do-FlushDns }
    if ($WinsockReset)        { Do-WinsockReset }
}

Write-Host ""
Out-Msg -Level ACTION -Message "Re-scanning devices (pnputil /scan-devices)" -Indent 1
& pnputil.exe /scan-devices | Out-File (Join-Path $script:CurrentBackup 'ScanDevices.txt') -Append
Write-Host ""
Out-Msg -Level OK -Message "Completed. Log: $script:LogFile  Backups: $script:CurrentBackup"
