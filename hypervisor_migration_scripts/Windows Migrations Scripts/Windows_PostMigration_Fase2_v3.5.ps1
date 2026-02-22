<#
.SYNOPSIS
    Universal Post-Migration Script for Windows VMs (VMware to Hyper-V).
    Version 3.5

.DESCRIPTION
    This script performs post-migration tasks after a Windows VM has been
    migrated from VMware to Hyper-V. It automatically detects the PowerShell
    version and uses the appropriate cmdlets for maximum compatibility.

    What it does:
    - Phase 1: Imports the network backup created by the Pre-Migration script (Phase 1)
    - Phase 2: Restores IP, Gateway, DNS, and adapter names by matching MAC addresses
    - Phase 3: Disables IPv6 on all adapters (common enterprise requirement)
    - Phase 4: Validates and fixes data disks (online, writable, drive letters)

    Designed for restricted enterprise environments:
    - No internet access required
    - No external modules or software installation needed
    - Uses only built-in Windows/PowerShell cmdlets
    - Runs in PowerShell ISE as Administrator

.NOTES
    Author:  Luciano Patrão
    License: MIT
    GitHub:  https://github.com/yourrepo

    Tested on:
    - Windows Server 2012 R2 (PowerShell 3.0/4.0)
    - Windows Server 2016 (PowerShell 5.1)
    - Windows Server 2019 (PowerShell 5.1)
    - Windows Server 2022 (PowerShell 5.1)

    Changelog:
    v3.5 - English translation, sanitized for public release
    v3.0.1 - Added storage diagnostics before capacity errors, CSV report export
    v2.7   - Global safeguard: skip Disk 1 operations if Disk 1 doesn't exist
    v2.6   - Refactored disk validation with dual-path (Storage module + diskpart)

.EXAMPLE
    # Run in PowerShell ISE as Administrator
    .\Windows_PostMigration_Fase2_v3.5.ps1
#>

Clear-Host

# ============================================================
# CONFIGURATION - Adjust these settings for your environment
# ============================================================
$workingDir = "C:\Migration"                                       # Must match the Pre-Migration script path
$BackupFile = Join-Path $workingDir "network_backup.xml"           # Network backup from Phase 1

# ============================================================
# EXECUTION - Do not modify below this line
# ============================================================

# --- Phase 0: Administrator Check ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run with Administrator privileges. Please open PowerShell as Administrator and try again."
    exit 1
}

Write-Host "============================================================"
Write-Host "  Windows VM Post-Migration Script (VMware to Hyper-V)"
Write-Host "  Version 3.5"
Write-Host "============================================================"
Write-Host ""

# ============================================================
# Phase 1: Import Network Configuration from Backup
# ============================================================
Write-Host "--- Phase 1: Importing network configuration from '$BackupFile' ---" -ForegroundColor Cyan
if (-not (Test-Path $BackupFile)) {
    Write-Error "Backup file '$BackupFile' not found! Make sure Phase 1 (Pre-Migration) was run first."
    exit 1
}
$restoredConfigurations = Import-CliXml -Path $BackupFile

# --- Helper function: Convert CIDR prefix length to subnet mask (PSv3 compatible) ---
function Convert-PrefixToSubnetMask {
    param($PrefixLength)
    $byteArray = [byte[]]([System.Linq.Enumerable]::Repeat([byte]255, $PrefixLength) + [System.Linq.Enumerable]::Repeat([byte]0, 32 - $PrefixLength))
    $ipObject = New-Object System.Net.IPAddress -ArgumentList (,$byteArray)
    return $ipObject.ToString()
}

# ============================================================
# Phase 2: Restore Network Configuration
# ============================================================
Write-Host "`n--- Phase 2: Applying network settings to adapters ---" -ForegroundColor Cyan
foreach ($config in $restoredConfigurations) {
    Write-Host "`nProcessing adapter with original name: '$($config.OriginalName)' (MAC: $($config.MACAddress))" -ForegroundColor Yellow

    if ($PSVersionTable.PSVersion.Major -ge 4) {
        # --- MODERN CODE PATH (PowerShell 4.0+) ---
        $targetAdapter = Get-NetAdapter | Where-Object { $_.MacAddress -eq $config.MACAddress } -ErrorAction SilentlyContinue
        if (-not $targetAdapter) { Write-Warning "WARNING: No network adapter found with MAC Address '$($config.MACAddress)'. Skipping."; continue }

        $currentIpConfig = Get-NetIPConfiguration -InterfaceIndex $targetAdapter.ifIndex
        $savedPrimaryIp = $config.IPAddresses[0]
        $currentPrimaryIp = $currentIpConfig.IPv4Address | Select-Object -First 1

        if ($currentPrimaryIp -and $currentPrimaryIp.IPAddress -eq $savedPrimaryIp.IPAddress -and $currentPrimaryIp.PrefixLength -eq $savedPrimaryIp.PrefixLength) {
            Write-Host "  > Validation: IP configuration for '$($config.OriginalName)' is already correct. Skipping." -ForegroundColor Green
        } else {
            Write-Host "  > Adapter found: '$($targetAdapter.Name)'. Renaming to '$($config.OriginalName)'..."
            Rename-NetAdapter -Name $targetAdapter.Name -NewName $config.OriginalName -ErrorAction SilentlyContinue | Out-Null
            $targetAdapter = Get-NetAdapter -Name $config.OriginalName

            Write-Host "  > Clearing existing IP configuration..."
            Get-NetIPAddress -InterfaceIndex $targetAdapter.ifIndex | Remove-NetIPAddress -Confirm:$false | Out-Null

            if ($config.IPAddresses) {
                foreach ($ip in $config.IPAddresses) {
                    Write-Host "  > Applying IP address: $($ip.IPAddress)/$($ip.PrefixLength)"
                    New-NetIPAddress -InterfaceIndex $targetAdapter.ifIndex -IPAddress $ip.IPAddress -PrefixLength $ip.PrefixLength -ErrorAction Stop | Out-Null
                }
            }

            if ($config.DefaultGateway) {
                $gateway = @($config.DefaultGateway)[0]
                if ($gateway) {
                    Write-Host "  > Setting default gateway to: $gateway"
                    $existingRoute = Get-NetRoute -InterfaceIndex $targetAdapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
                    if ($existingRoute) {
                        Write-Host "    - Default route exists. Updating gateway..."
                        Set-NetRoute -InputObject $existingRoute -NextHop $gateway -ErrorAction Stop | Out-Null
                    } else {
                        Write-Host "    - No default route found. Creating new one..."
                        New-NetRoute -DestinationPrefix "0.0.0.0/0" -InterfaceIndex $targetAdapter.ifIndex -NextHop $gateway -ErrorAction Stop | Out-Null
                    }
                }
            }

            if ($config.DNSServers) {
                Write-Host "  > Applying DNS servers: $($config.DNSServers -join ', ')"
                Set-DnsClientServerAddress -InterfaceIndex $targetAdapter.ifIndex -ServerAddresses ($config.DNSServers) -ErrorAction Stop | Out-Null
            }

            Write-Host "  > Configuration applied for '$($config.OriginalName)'." -ForegroundColor Green
        }
    } else {
        # --- LEGACY CODE PATH (PowerShell 3.0 and earlier) ---
        $targetAdapter = Get-WmiObject -Class Win32_NetworkAdapter | Where-Object { $_.MACAddress -eq $config.MACAddress }
        if (-not $targetAdapter) { Write-Warning "WARNING: No network adapter found with MAC Address '$($config.MACAddress)'. Skipping."; continue }

        $currentConfigWmi = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "Index=$($targetAdapter.Index)"
        $savedPrimaryIp = $config.IPAddresses[0]
        $currentPrimaryIpAddress = @($currentConfigWmi.IPAddress)[0]
        $currentSubnetMask = @($currentConfigWmi.IPSubnet)[0]
        $currentPrefixLength = 0
        if ($currentSubnetMask) {
            $currentPrefixLength = (($(([System.Net.IPAddress]$currentSubnetMask).GetAddressBytes() | ForEach-Object { [convert]::ToString($_, 2).PadLeft(8, '0') } | Out-String).Replace("`r`n", "").ToCharArray() | Where-Object {$_ -eq '1' }) | Measure-Object).Count
        }

        if ($currentPrimaryIpAddress -eq $savedPrimaryIp.IPAddress -and $currentPrefixLength -eq $savedPrimaryIp.PrefixLength) {
            Write-Host "  > Validation: IP configuration for '$($config.OriginalName)' is already correct. Skipping." -ForegroundColor Green
        } else {
            Write-Host "  > Legacy PS: Found '$($targetAdapter.Name)'. Renaming and applying settings using netsh..."
            $currentName = $targetAdapter.Name
            netsh interface set interface name="$currentName" newname="$($config.OriginalName)"
            Start-Sleep -Seconds 3
            $newName = $config.OriginalName

            if ($config.IPAddresses) {
                $primaryIP = $config.IPAddresses[0]
                $subnetMask = Convert-PrefixToSubnetMask -PrefixLength $primaryIP.PrefixLength
                $gateway = if ($config.DefaultGateway) { @($config.DefaultGateway)[0] } else { "none" }
                netsh interface ip set address name="$newName" static $($primaryIP.IPAddress) $subnetMask $gateway

                if ($config.IPAddresses.Count -gt 1) {
                    for ($i = 1; $i -lt $config.IPAddresses.Count; $i++) {
                        $secondaryIP = $config.IPAddresses[$i]
                        $secondaryMask = Convert-PrefixToSubnetMask -PrefixLength $secondaryIP.PrefixLength
                        netsh interface ip add address name="$newName" $($secondaryIP.IPAddress) $secondaryMask
                    }
                }
            }

            if ($config.DNSServers) {
                netsh interface ip set dns name="$newName" static $($config.DNSServers[0])
                if ($config.DNSServers.Count -gt 1) {
                    for ($i = 1; $i -lt $config.DNSServers.Count; $i++) {
                        netsh interface ip add dns name="$newName" $($config.DNSServers[$i]) index=($i+1)
                    }
                }
            }

            Write-Host "  > Configuration applied for '$($config.OriginalName)'." -ForegroundColor Green
        }
    }
}

# ============================================================
# Phase 3: Disable IPv6
# ============================================================
Write-Host "`n--- Phase 3: Disabling IPv6 on all adapters ---" -ForegroundColor Cyan
if (Get-Command Get-NetAdapterBinding -ErrorAction SilentlyContinue) {
    Get-NetAdapterBinding -ComponentID ms_tcpip6 | Disable-NetAdapterBinding -Confirm:$false
    Write-Host "  > IPv6 protocol disabled (Modern Method)." -ForegroundColor Green
} else {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"
    if (!(Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    Set-ItemProperty -Path $regPath -Name "DisabledComponents" -Value 0xFFFFFFFF -Type DWord -Force
    Write-Host "  > IPv6 protocol disabled via registry (Legacy Method)." -ForegroundColor Green
    Write-Warning "A REBOOT is required for the IPv6 change to take effect."
}

# ============================================================
# Phase 4: Validate and Fix Data Disks
# ============================================================
Write-Host "`n--- Phase 4: Validating and fixing data disks ---" -ForegroundColor Cyan

$ErrorActionPreference = 'Stop'

# --- Helper output functions ---
function Write-Phase([string]$msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Step ([string]$msg) { Write-Host "  > $msg" -ForegroundColor Yellow }
function Write-OK   ([string]$msg) { Write-Host "    - $msg" -ForegroundColor Green }
function Write-Warn ([string]$msg) { Write-Host "    - $msg" -ForegroundColor Magenta }
function Write-Fail ([string]$msg) { Write-Host "    - $msg" -ForegroundColor Red }

# Try to import Storage module if available
$HasStorageModule = $false
try {
    $null = Import-Module Storage -ErrorAction Stop
    $HasStorageModule = $true
} catch {}

# --- Execute diskpart with a script string ---
function Run-Diskpart {
    param([Parameter(Mandatory)] [string]$ScriptContent)

    $tmp = New-TemporaryFile
    Set-Content -Path $tmp -Value $ScriptContent -Encoding ASCII -NoNewline
    try {
        $out = & diskpart.exe /s $tmp 2>&1
        return $out
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

# --- Move CD/DVD from D: to Z: using CIM (works for optical drives) ---
function Move-CDROM-FromD-ToZ {
    $cd = Get-CimInstance Win32_Volume -Filter "DriveLetter='D:' AND DriveType=5" -ErrorAction SilentlyContinue
    if ($cd) {
        Write-Step "CD/DVD drive is using 'D:'. Moving to 'Z:'..."
        Set-CimInstance -InputObject $cd -Property @{ DriveLetter = 'Z:' }
        Write-OK "CD/DVD now on 'Z:'."
        return $true
    }
    return $false
}

# --- Ensure disk is online and writable ---
function Ensure-Disk-Online {
    param([Parameter(Mandatory)][int]$DiskNumber)

    if ($HasStorageModule) {
        $d = Get-Disk -Number $DiskNumber -ErrorAction Stop
        if ($d.IsOffline) {
            Write-Step "Bringing Disk $DiskNumber online..."
            Set-Disk -Number $DiskNumber -IsOffline:$false
        }
        if ($d.IsReadOnly) {
            Write-Step "Removing read-only from Disk $DiskNumber..."
            Set-Disk -Number $DiskNumber -IsReadOnly:$false
        }
        Write-OK "Disk $DiskNumber is online and writable."
    } else {
        Write-Step "No Storage module. Using diskpart for Disk $DiskNumber..."
        $script = @"
select disk $DiskNumber
online disk
attributes disk clear readonly
"@
        $null = Run-Diskpart -ScriptContent $script
        Write-OK "Disk $DiskNumber online (diskpart)."
    }
}

# --- Get target data partition on Disk 1 (largest usable partition) ---
function Get-Target-Partition-OnDisk1 {
    if ($HasStorageModule) {
        $parts = Get-Partition -DiskNumber 1 -ErrorAction Stop | Where-Object {
            $_.Type -notmatch 'Reserved' -and $_.GptType -ne '{E3C9E316-0B5C-4DB8-817D-F92DF00215AE}'
        } | Sort-Object Size -Descending
        return $parts | Select-Object -First 1
    } else {
        # Fallback via WMI/CIM
        $parts = Get-CimInstance -ClassName Win32_DiskPartition -Filter "DiskIndex=1" |
            Where-Object { $_.Type -notmatch 'Reserved' } |
            Sort-Object Size -Descending
        return $parts | Select-Object -First 1
    }
}

# --- Remove an existing drive letter before reassignment ---
function Remove-DriveLetter {
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Z]$')][string]$DriveLetter
    )
    if ($HasStorageModule) {
        $vol = Get-Volume -DriveLetter $DriveLetter -ErrorAction SilentlyContinue
        if ($vol) {
            $part = Get-Partition -DriveLetter $DriveLetter -ErrorAction SilentlyContinue
            if ($part) {
                Write-Step "Removing letter '$($DriveLetter):' from partition $($part.PartitionNumber) (Storage)..."
                Remove-PartitionAccessPath -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -AccessPath "$($DriveLetter):\" -ErrorAction Stop
                Write-OK "Letter '$($DriveLetter):' removed."
            } else {
                # If Get-Partition fails, try via CIM
                Write-Step "Letter '$($DriveLetter):' present without known partition. Releasing via CIM..."
                $cvol = Get-CimInstance Win32_Volume -Filter "DriveLetter='$($DriveLetter):'" -ErrorAction SilentlyContinue
                if ($cvol) { Set-CimInstance -InputObject $cvol -Property @{ DriveLetter = $null } }
                Write-OK "Letter '$($DriveLetter):' released (CIM)."
            }
        }
    } else {
        Write-Step "Removing letter '$($DriveLetter):' (diskpart)..."
        $script = @"
select volume=$DriveLetter
remove letter=$DriveLetter
"@
        $null = Run-Diskpart -ScriptContent $script
        Write-OK "Letter '$($DriveLetter):' removed (diskpart)."
    }

    # Hard cleanup: mountvol (handles orphaned entries)
    Write-Step "Cleaning up possible orphaned entries for '$($DriveLetter):' with mountvol..."
    & mountvol.exe "$($DriveLetter):" /D 2>$null | out-null
}

# --- Force full release of a drive letter (scans all partitions/volumes) ---
function Free-DriveLetter {
    param([Parameter(Mandatory)][ValidatePattern('^[A-Z]$')][string]$Letter)

    Write-Step "Ensuring '$($Letter):' is free..."
    try { Remove-DriveLetter -DriveLetter $Letter } catch {}

    # In some cases there are multiple access paths. Remove from all known partitions.
    if ($HasStorageModule) {
        $parts = Get-Partition | Where-Object { $_.AccessPaths -and $_.AccessPaths -match "^$($Letter):\\" }
        foreach ($p in $parts) {
            Write-Step "Removing residual access path on Disk $($p.DiskNumber), Partition $($p.PartitionNumber)..."
            Remove-PartitionAccessPath -DiskNumber $p.DiskNumber -PartitionNumber $p.PartitionNumber -AccessPath "$($Letter):\" -ErrorAction SilentlyContinue
        }
    }

    # Additional CIM sweep
    $vols = Get-CimInstance Win32_Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -eq "$($Letter):" }
    foreach ($v in $vols) {
        Write-Step "Releasing letter '$($Letter):' via CIM (volume id $($v.DeviceID))..."
        try { Set-CimInstance -InputObject $v -Property @{ DriveLetter = $null } } catch {}
    }
}

# --- Assign drive letter via Storage module or diskpart ---
function Assign-DriveLetter {
    param(
        [Parameter(Mandatory)][int]$DiskNumber,
        [Parameter(Mandatory)][int]$PartitionNumber,
        [Parameter(Mandatory)][ValidatePattern('^[A-Z]$')][string]$Letter
    )

    if ($HasStorageModule) {
        Write-Step "Assigning letter '$($Letter):' to partition $PartitionNumber on Disk $DiskNumber..."
        Set-Partition -DiskNumber $DiskNumber -PartitionNumber $PartitionNumber -NewDriveLetter $Letter
        Write-OK "Letter '$($Letter):' assigned (Storage)."
    } else {
        Write-Step "Assigning letter '$($Letter):' (diskpart)..."
        $script = @"
select disk $DiskNumber
select partition $PartitionNumber
assign letter=$Letter
"@
        $out = Run-Diskpart -ScriptContent $script
        if ($out -match 'successfully assigned the drive letter') {
            Write-OK "Letter '$($Letter):' assigned (diskpart)."
        } else {
            Write-Warn "Please verify the assignment via diskpart:"
            $out | ForEach-Object { Write-Host "      $_" }
        }
    }
}

# ============================================================
# Phase 4 - Execution
# ============================================================

Write-Host "============================================================"
Write-Host "--- Starting Post-Migration Data Disk Validation ---"
Write-Host "============================================================"

try {
    Write-Phase "Step 1: Environment detection"
    if ($HasStorageModule) {
        Write-OK "Storage module available. Using modern cmdlets."
    } else {
        Write-Warn "Storage module unavailable. Using diskpart/CIM fallback."
    }

    Write-Phase "Step 2: Process Disk 1 and drive letter D"

    # --- Global safeguard: only touch CD/DVD and Disk 1 if Disk 1 exists ---
    if ($HasStorageModule) {
        $allDisks = Get-Disk -ErrorAction SilentlyContinue
    } else {
        $allDisks = @( Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{ Number = [int]$_.Index }
        })
    }
    $hasDisk1 = $allDisks | Where-Object { $_.Number -eq 1 }

    if (-not $hasDisk1) {
        Write-Host "  > No Disk 1 found on this system. Skipping D: remapping and all Disk 1 operations." -ForegroundColor Yellow
    } else {
        # 2.1 Move CD/DVD if it's on D: (only when Disk 1 exists)
        if ($HasStorageModule) {
            if (Get-Disk -Number 1 -ErrorAction SilentlyContinue) {
                $null = Move-CDROM-FromD-ToZ
            } else {
                Write-Host "  > Safeguard: Disk 1 not available at this time. Not changing CD/DVD letter." -ForegroundColor Yellow
            }
        } else {
            # In legacy mode, Disk 1 presence was already confirmed via WMI
            $null = Move-CDROM-FromD-ToZ
        }

        # 2.2 Ensure Disk 1 is online and writable
        if ($HasStorageModule) {
            $disk1Present = Get-Disk -Number 1 -ErrorAction SilentlyContinue
        } else {
            $disk1Present = Get-CimInstance -ClassName Win32_DiskDrive -Filter "Index=1" -ErrorAction SilentlyContinue
        }
        if ($disk1Present) {
            Ensure-Disk-Online -DiskNumber 1
        } else {
            throw "Disk 1 is no longer available during the operation."
        }

        # 2.3 Get target data partition on Disk 1
        $targetPart = Get-Target-Partition-OnDisk1
        if (-not $targetPart) {
            throw "No valid partition found on Disk 1."
        }

        # Normalize properties when coming from CIM
        if ($targetPart.PSObject.TypeNames -contains 'Microsoft.Management.Infrastructure.CimInstance#ROOT/cimv2/Win32_DiskPartition') {
            $partitionNumber = [int]$targetPart.Index
        } else {
            $partitionNumber = [int]$targetPart.PartitionNumber
        }

        # 2.4 Aggressively free D: before assigning
        Free-DriveLetter -Letter 'D'

        # 2.5 Assign D: to the target partition on Disk 1 with retry
        $assigned = $false
        try {
            Assign-DriveLetter -DiskNumber 1 -PartitionNumber $partitionNumber -Letter 'D'
            $assigned = $true
        } catch {
            if ($_.Exception.Message -match 'access path is already in use') {
                Write-Warn "D: still reports being in use. Cleaning up and retrying..."
                Free-DriveLetter -Letter 'D'
                Start-Sleep -Seconds 2
                Assign-DriveLetter -DiskNumber 1 -PartitionNumber $partitionNumber -Letter 'D'
                $assigned = $true
            } else {
                throw
            }
        }

        if ($assigned) { Write-OK "Drive letter D assigned to Disk 1." }
    }

    Write-Phase "Step 3: Ensure remaining disks are online"
    if ($HasStorageModule) {
        $dataDisks = Get-Disk | Where-Object { $_.Number -gt 0 } | Sort-Object Number
        foreach ($disk in $dataDisks) {
            Ensure-Disk-Online -DiskNumber $disk.Number
        }
    } else {
        # Fallback: list via WMI and bring online via diskpart
        $wmidisks = Get-CimInstance Win32_DiskDrive | Sort-Object Index
        foreach ($d in $wmidisks) {
            if ($d.Index -gt 0) {
                Ensure-Disk-Online -DiskNumber $d.Index
            }
        }
    }

    Write-Host "`n[SUCCESS] Disk validation and correction completed." -ForegroundColor Green
}
catch {
    Write-Fail "An error occurred during disk validation: $($_.Exception.Message)"
    exit 2
}

Write-Host "`n[SUCCESS] All disk validation and configuration completed." -ForegroundColor Green
Write-Host "`n[FINISHED] Post-migration process is complete." -ForegroundColor Green
