# =====================================================================================
# Name: PostCutover_Network_Sanity.ps1
# Created: 2025-08-31
# Author: Luciano Patrao (with colorized output and built-in restore)
#
# Purpose
#   Safe post-migration hygiene for Windows VMs moved off VMware to Hyper-V/Proxmox/etc.
#   - Preserve IP configuration by default
#   - Remove ONLY nonpresent VMware NICs
#   - Optional: Flush DNS, Winsock reset, DriverStore cleanup (VMware-only)
#   - Backups before changes
#   - Built-in RESTORE for drivers and (optional) IP settings
#
# Output style (like the original script)
#   - Color-coded messages (can disable with -NoColor)
#   - Indented actions/results
#   - Distinct levels: HEADER, ACTION, OK, WARN, ERROR, INFO
#
# Usage (run as Administrator)
#   .\PostCutover_Network_Sanity.ps1                          # default cleanup (no IP reset)
#   .\PostCutover_Network_Sanity.ps1 -FlushDns                # add DNS cache flush
#   .\PostCutover_Network_Sanity.ps1 -WinsockReset            # add Winsock reset (reboot recommended)
#   .\PostCutover_Network_Sanity.ps1 -RemoveDriverStore       # delete VMware-named DriverStore packages
#   .\PostCutover_Network_Sanity.ps1 -Restore                 # restore drivers from latest backup and exit
#   .\PostCutover_Network_Sanity.ps1 -Restore -BackupPath C:\PostMig\Backups\20250831_120000
#   .\PostCutover_Network_Sanity.ps1 -Restore -RestoreIP      # restore drivers and reapply saved IPs
#   .\PostCutover_Network_Sanity.ps1 -WhatIf                  # dry run (respects ShouldProcess)
# =====================================================================================

#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [switch]$Cleanup,
    [switch]$RemoveDriverStore,
    [switch]$FlushDns,
    [switch]$WinsockReset,
    [switch]$Restore,
    [switch]$RestoreIP,
    [string]$BackupPath,
    [switch]$NoColor
)

Clear-Host

# 0. Check if the script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run with Administrator privileges."
    exit 1
}

# Get system information
$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
Write-Host "Checking virtualization platform...   Hypervisor = $($computerSystem.Manufacturer)" -ForegroundColor Cyan
Write-Host ""

# --- Platform / Hypervisor check ---
if ($computerSystem.Manufacturer -like "*VMware*") {

    Write-Warning "This VM is running on VMware. This script should not be executed on VMware environments."

    Write-Host ""
    do {
        $resp1 = (Read-Host "Are you sure you want to continue? (y/n)").ToLower().Trim()
    } while (-not @('y','n','yes','no').Contains($resp1))

    if ($resp1.StartsWith('n')) {
        Write-Host ""
        Write-Host "Operation canceled by user." -ForegroundColor Red
        return
    }

    Write-Host ""
    do {
        $resp2 = (Read-Host "Confirm again to continue (second confirmation). Continue? (y/n)").ToLower().Trim()
    } while (-not @('y','n','yes','no').Contains($resp2))

    if ($resp2.StartsWith('n')) {
        Write-Host ""
        Write-Host "Operation canceled by user." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "User confirmed twice. Continuing script execution..." -ForegroundColor Green
}
else {
    # Do not validate Microsoft/Proxmox/other. Just inform and continue.
    $man   = $computerSystem.Manufacturer
    $model = $computerSystem.Model

    Write-Host ("[INFO] Detected hypervisor: {0} | Model: {1}. " -f $man, $model) -ForegroundColor Yellow -NoNewline
    Write-Host "Continuing..." -ForegroundColor Green
    Write-Host ""
}

# --- VMware Tools guard (must be removed before cleanup). Integrated without removing original code ---
function Get-VMwareToolsUninstallInfo {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($p in $paths) {
        Get-ChildItem $p -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue
            if ($props.DisplayName -and $props.DisplayName -like 'VMware Tools*') {
                return [pscustomobject]@{
                    DisplayName     = $props.DisplayName
                    UninstallString = $props.UninstallString
                    Publisher       = $props.Publisher
                    InstallLocation = $props.InstallLocation
                }
            }
        }
    }
    return $null
}
function Prompt-YesNo($question) {
    do { $r = (Read-Host "$question (y/n)").ToLower().Trim() } while ($r -notin @('y','n','yes','no'))
    return -not $r.StartsWith('n')
}

$vmtools = Get-VMwareToolsUninstallInfo
if ($vmtools) {
    Write-Warning ("VMware Tools detected: {0}. This script should not run until VMware Tools is removed." -f $vmtools.DisplayName)

    if (-not (Prompt-YesNo "Do you want to uninstall VMware Tools now and exit")) {
        Write-Host "Please uninstall VMware Tools manually, reboot, then run this script again." -ForegroundColor Yellow
        return
    }

    if (-not (Prompt-YesNo "Confirm again to uninstall VMware Tools now")) {
        Write-Host "Operation canceled by user." -ForegroundColor Red
        return
    }

    # Try to stop VMware Tools services before uninstall
    'VMTools','VMUSBArbService' | ForEach-Object {
        try { Stop-Service $_ -ErrorAction SilentlyContinue } catch {}
    }

    # Build silent uninstall command
    $cmd = $null; $args = $null
    $u = $vmtools.UninstallString
    if ($u -match '(?i)msiexec') {
        $normalized = $u -replace '/I', '/X'
        $cmd = 'msiexec.exe'
        $args = ($normalized -replace '(?i)msiexec(\.exe)?\s*', '') + ' /qn REBOOT=ReallySuppress'
    } else {
        $parts = [System.Text.RegularExpressions.Regex]::Split($u, '\s+', 2)
        $cmd = $parts[0]
        $args = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        if ($args -notmatch '(?i)/s|/silent|/qn|/quiet') { $args = "$args /s" }
        if ($args -notmatch '(?i)REBOOT=ReallySuppress') { $args = "$args REBOOT=ReallySuppress" }
    }

    Write-Host "Uninstalling VMware Tools silently..." -ForegroundColor Cyan
    try {
        $p = Start-Process -FilePath $cmd -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
        $code = $p.ExitCode
        $rebootNeeded = ($code -eq 3010)
        if ($code -eq 0 -or $rebootNeeded) {
            Write-Host ("Uninstall completed (exit {0})." -f $code) -ForegroundColor Green
        } else {
            Write-Host ("Uninstall returned exit code {0}." -f $code) -ForegroundColor Yellow
        }
        Write-Host "Reboot required. Please reboot, then run this script again." -ForegroundColor Yellow
    } catch {
        Write-Host ("Failed to launch uninstall: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
    return
}
# --- end VMware Tools guard ---

# ------------------- Helpers -------------------
function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
               ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw "Run as Administrator." }
}

function New-PathSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { $null = New-Item -ItemType Directory -Path $Path -Force }
}

# Logging + Console output with levels and colors
$script:UseColor = -not $NoColor
$script:LogRoot  = 'C:\PostMig\Logs'
$script:BackupRoot = 'C:\PostMig\Backups'

function Initialize-Log {
    New-PathSafe $script:LogRoot
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:LogFile = Join-Path $script:LogRoot ("PostCutover_Network_Sanity_{0}.log" -f $ts)
}

function Write-LogLine {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    $line | Out-File -FilePath $script:LogFile -Encoding UTF8 -Append
}

function Out-Msg {
    param(
        [ValidateSet('HEADER','ACTION','OK','WARN','ERROR','INFO')][string]$Level = 'INFO',
        [string]$Message,
        [int]$Indent = 0
    )
    $pad = ' ' * ($Indent * 2)
    $prefix = switch ($Level) {
        'HEADER' { '==>' }
        'ACTION' { '  >' }
        'OK'     { '    OK' }
        'WARN'   { '    WARN' }
        'ERROR'  { '    ERR' }
        default  { '    .' }
    }
    $text = "{0}[{1}] {2}" -f $pad, $prefix, $Message
    Write-LogLine -Message $Message -Level $Level
    if ($script:UseColor) {
        $color = switch ($Level) {
            'HEADER' { 'Cyan' }
            'ACTION' { 'Cyan' }
            'OK'     { 'Green' }
            'WARN'   { 'Yellow' }
            'ERROR'  { 'Red' }
            default  { 'Gray' }
        }
        Write-Host $text -ForegroundColor $color
    } else {
        Write-Host $text
    }
}

function Get-LatestBackupFolder {
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root)) { return $null }
    $dirs = Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($dirs) { return $dirs[0].FullName } else { return $null }
}

function Export-Backups {
    param([string]$DestRoot)
    $dest = Join-Path $DestRoot (Get-Date -Format "yyyyMMdd_HHmmss")
    New-PathSafe $dest
    Out-Msg -Level ACTION -Message "Exporting DriverStore" -Indent 1
    $drv = Join-Path $dest 'Drivers'
    New-PathSafe $drv
    & pnputil.exe /export-driver * $drv | Out-File -FilePath (Join-Path $dest 'DriverExport.txt') -Append

    Out-Msg -Level ACTION -Message "Saving PnP device inventory (present and nonpresent)" -Indent 1
    Get-PnpDevice -PresentOnly:$false | Select-Object InstanceId, Class, FriendlyName, Manufacturer, Present, Status |
        Export-Csv -Path (Join-Path $dest 'DeviceInventory.csv') -NoTypeInformation -Encoding UTF8

    Out-Msg -Level ACTION -Message "Saving current IP configuration snapshot" -Indent 1
    $netSnap = Get-NetIPConfiguration | Select-Object InterfaceAlias, InterfaceIndex, InterfaceDescription, NetProfile.Name,
        @{n="IPv4";e={$_.IPv4Address.IPAddress}}, @{n="IPv4PrefixLength";e={$_.IPv4Address.PrefixLength}},
        @{n="IPv4Gateway";e={$_.IPv4DefaultGateway.NextHop}},
        @{n="DNSServers";e={(Get-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4).ServerAddresses -join ","}},
        @{n="DHCPEnabled";e={(Get-NetIPInterface -InterfaceIndex $_.InterfaceIndex).Dhcp}},
        @{n="MAC";e={(Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue).MacAddress}}
    $netSnap | Export-Csv -Path (Join-Path $dest 'IPConfig.csv') -NoTypeInformation -Encoding UTF8
    $netSnap | ConvertTo-Json -Depth 4 | Out-File -FilePath (Join-Path $dest 'IPConfig.json') -Encoding UTF8

        Out-Msg -Level OK -Message "Backups created at $dest" -Indent 1
        Write-Host ""
    return $dest
}

function Remove-GhostVmwareNics {
    Out-Msg -Level ACTION -Message "Searching for NONPRESENT VMware NICs" -Indent 1
    $ghostNics = Get-PnpDevice -PresentOnly:$false | Where-Object {
        $_.Class -eq 'Net' -and -not $_.Present -and ($_.FriendlyName -match 'VMware|vmxnet')
    }
    if ($ghostNics) {
        foreach ($nic in $ghostNics) {
            $msg = ("Removing nonpresent NIC: {0} ({1})" -f $nic.FriendlyName, $nic.InstanceId)
            if ($PSCmdlet.ShouldProcess($nic.InstanceId, "Remove-PnpDevice")) {
                try {
                    Remove-PnpDevice -InstanceId $nic.InstanceId -Confirm:$false -ErrorAction Stop
                    Out-Msg -Level OK -Message $msg -Indent 2
                } catch {
                    Out-Msg -Level WARN -Message ("Failed to remove {0}: {1}" -f $nic.InstanceId, $_.Exception.Message) -Indent 2
                }
            } else {
                Out-Msg -Level INFO -Message ("WhatIf: would remove {0}" -f $nic.InstanceId) -Indent 2
            }
        }
    } else {
        Out-Msg -Level INFO -Message "No nonpresent VMware NICs found" -Indent 2
        Write-Host ""
    }
}

function Cleanup-DriverStoreVmware {
    Out-Msg -Level ACTION -Message "Enumerating DriverStore for VMware-named drivers" -Indent 1
    Write-Host ""
    $enum = & pnputil.exe /enum-drivers
    $oemSet = @()
    $current = @{}
    foreach ($line in $enum) {
        if     ($line -match 'Published Name\s*:\s*(oem\d+\.inf)') { $current['Name'] = $Matches[1] }
        elseif ($line -match 'Provider Name\s*:\s*(.*)')          { $current['Provider'] = $Matches[1].Trim() }
        elseif ($line -match 'Class Name\s*:\s*(.*)')             { $current['Class'] = $Matches[1].Trim() }
        elseif ($line -match 'Driver Name\s*:\s*(.*)')            {
            $current['Driver'] = $Matches[1].Trim()
            if ($current['Name']) { $oemSet += [pscustomobject]$current; $current = @{} }
        }
    }
    $vmwOems = $oemSet | Where-Object { $_.Provider -match 'VMware' -or $_.Driver -match 'vmxnet|pvscsi|vmci|vmmouse|svga' }
    if (-not $vmwOems) { Out-Msg -Level INFO -Message "No VMware-named DriverStore packages found" -Indent 2; return }
    foreach ($oem in $vmwOems) {
        if ($PSCmdlet.ShouldProcess($oem.Name, "Delete VMware driver from DriverStore")) {
            try {
                & pnputil.exe /delete-driver $oem.Name /uninstall /force | Out-File -FilePath (Join-Path $script:CurrentBackup 'DriverStoreRemoval.txt') -Append
                Out-Msg -Level OK -Message ("Deleted DriverStore package {0} [{1}]" -f $oem.Name, $oem.Driver) -Indent 2
            } catch {
                Out-Msg -Level WARN -Message ("Failed to delete {0}: {1}" -f $oem.Name, $_.Exception.Message) -Indent 2
            }
        } else {
            Out-Msg -Level INFO -Message ("WhatIf: would delete {0}" -f $oem.Name) -Indent 2
        }
    }
}

function Restore-Drivers {
    param([string]$FromPath)
    $drivers = Join-Path $FromPath 'Drivers'
    if (-not (Test-Path -LiteralPath $drivers)) { throw "Drivers folder not found in backup: $FromPath" }
    Out-Msg -Level ACTION -Message "Restoring drivers from $drivers" -Indent 1
    & pnputil.exe /add-driver "$drivers\*.inf" /subdirs /install | Out-File -FilePath (Join-Path $FromPath 'RestoreDrivers.txt') -Append
    Out-Msg -Level OK -Message "Driver restore completed" -Indent 1
}

function Restore-IPs {
    param([string]$FromPath)
    $json = Join-Path $FromPath 'IPConfig.json'
    if (-not (Test-Path -LiteralPath $json)) { throw "IPConfig.json not found in backup: $FromPath" }
    Out-Msg -Level ACTION -Message "Restoring IP settings from $json" -Indent 1
    $snap = Get-Content $json -Raw | ConvertFrom-Json
    foreach ($i in $snap) {
        $nic = $null
        if ($i.MAC) { $nic = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.MacAddress -eq $i.MAC } | Select-Object -First 1 }
        if (-not $nic -and $i.InterfaceAlias) { $nic = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $i.InterfaceAlias } | Select-Object -First 1 }
        if (-not $nic) { Out-Msg -Level WARN -Message ("Skip: could not map saved interface for {0}" -f $i.InterfaceAlias) -Indent 2; continue }

        if ($PSCmdlet.ShouldProcess($nic.Name, "Apply saved IP/DNS")) {
            try {
                if ($i.DHCPEnabled -eq "Enabled") {
                    Set-NetIPInterface -InterfaceAlias $nic.Name -Dhcp Enabled -ErrorAction SilentlyContinue
                    Set-DnsClientServerAddress -InterfaceAlias $nic.Name -ResetServerAddresses -ErrorAction SilentlyContinue
                } else {
                    Get-NetIPAddress -InterfaceAlias $nic.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                        Where-Object { $_.PrefixOrigin -ne "WellKnown" } |
                        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
                    if ($i.IPv4) {
                        New-NetIPAddress -InterfaceAlias $nic.Name -IPAddress $i.IPv4 -PrefixLength $i.IPv4PrefixLength -DefaultGateway $i.IPv4Gateway -ErrorAction SilentlyContinue
                    }
                    if ($i.DNSServers) {
                        $dns = $i.DNSServers -split ","
                        Set-DnsClientServerAddress -InterfaceAlias $nic.Name -ServerAddresses $dns -ErrorAction SilentlyContinue
                    }
                }
                Out-Msg -Level OK -Message ("Applied IP to {0}" -f $nic.Name) -Indent 2
            } catch {
                Out-Msg -Level WARN -Message ("Failed to apply IP to {0}: {1}" -f $nic.Name, $_.Exception.Message) -Indent 2
            }
        } else {
            Out-Msg -Level INFO -Message ("WhatIf: would apply IP to {0}" -f $nic.Name) -Indent 2
        }
    }
}

# ------------------- Main -------------------
Assert-Admin
Initialize-Log

Out-Msg -Level HEADER -Message "PostCutover_Network_Sanity.ps1 starting"
Write-Host ""

# Restore path if requested
if ($Restore) {
    $src = $BackupPath
    if (-not $src -or -not (Test-Path -LiteralPath $src)) {
        $src = Get-LatestBackupFolder -Root $script:BackupRoot
        if (-not $src) { throw "No backups found in $($script:BackupRoot)" }
        Out-Msg -Level INFO -Message "Using latest backup: $src" -Indent 1
    } else {
        Out-Msg -Level INFO -Message "Using provided backup path: $src" -Indent 1
    }

    Restore-Drivers -FromPath $src
    if ($RestoreIP) {
        Restore-IPs -FromPath $src
    } else {
        Out-Msg -Level INFO -Message "IP restore not requested (-RestoreIP). Leaving IP settings unchanged." -Indent 1
    }
    Out-Msg -Level OK -Message "Restore complete" -Indent 1
    return
}

# Backup phase
try {
    New-PathSafe $script:BackupRoot
    $script:CurrentBackup = Export-Backups -DestRoot $script:BackupRoot
} catch {
    Out-Msg -Level WARN -Message ("Backup phase reported: {0}" -f $_.Exception.Message) -Indent 1
}

# Detect VMware presence (informational only)
$vmwarePresent = Get-PnpDevice | Where-Object { $_.FriendlyName -match 'VMware|vmxnet|pvscsi|vmci|vmmouse|svga' }
if ($vmwarePresent) {
    Out-Msg -Level WARN -Message "Detected VMware-related PRESENT devices. Ensure Tools were removed pre-migration." -Indent 1
}

# Remove nonpresent VMware NICs only
Remove-GhostVmwareNics

# Optional DriverStore cleanup (VMware-named only)
if ($RemoveDriverStore) { Cleanup-DriverStoreVmware }

# Optional lightweight network refresh
if ($FlushDns) {
    Out-Msg -Level ACTION -Message "Flushing DNS cache" -Indent 1
    & ipconfig.exe /flushdns | Out-File -FilePath (Join-Path $script:CurrentBackup 'DnsFlush.txt') -Append
    Out-Msg -Level OK -Message "DNS cache flushed" -Indent 2
}
if ($WinsockReset) {
    Out-Msg -Level ACTION -Message "Winsock reset requested" -Indent 1
    & netsh.exe winsock reset | Out-File -FilePath (Join-Path $script:CurrentBackup 'WinsockReset.txt') -Append
    Out-Msg -Level WARN -Message "A reboot is recommended after a Winsock reset" -Indent 2
}

# Rescan devices
Out-Msg -Level ACTION -Message "Re-scanning devices (pnputil /scan-devices)" -Indent 1
& pnputil.exe /scan-devices | Out-File -FilePath (Join-Path $script:CurrentBackup 'ScanDevices.txt') -Append
Write-Host ""
Out-Msg -Level OK -Message "Completed. Log: $script:LogFile  Backups: $script:CurrentBackup"