<#
.SYNOPSIS
    Universal Pre-Migration Script for Windows VMs (VMware to Hyper-V).
    Version 1.0 — GPO / Unattended Edition

.DESCRIPTION
    Non-interactive version designed for deployment via Group Policy (GPO)
    as a Computer Startup Script on an AD Organizational Unit (OU).

    This script runs fully unattended with no user prompts. All options
    are controlled via parameters or the configuration block below.

    What it does:
    - Phase 1: Backs up the current network configuration (IP, DNS, Gateway, MAC)
    - Phase 2: Creates a local administrator account for migration purposes
    - Phase 3: Optionally uninstalls VMware Tools (silent, no prompt)
    - Phase 4: (Optional) Shuts down the VM after completion

    All output is written to a per-VM log file for auditing.

    Designed for restricted enterprise environments:
    - No internet access required
    - No external modules or software installation needed
    - Uses only built-in Windows/PowerShell cmdlets
    - Runs silently via GPO (no console interaction)

.PARAMETER Password
    The password for the migration user account. Required.
    Can be passed via GPO script parameters.

.PARAMETER RemoveVMwareTools
    If specified, VMware Tools will be silently uninstalled without prompting.

.PARAMETER ShutdownAfter
    If specified, the VM will shut down after the script completes.

.PARAMETER MigrationUser
    Name of the local administrator account to create. Default: migrationadmin

.PARAMETER WorkingDir
    Working directory for backup and log files. Default: C:\Migration

.NOTES
    Author:  Luciano Patrão
    License: MIT
    GitHub:  https://github.com/yourrepo

    GPO Deployment:
      Computer Configuration → Policies → Windows Settings → Scripts → Startup
      Script: Windows_PreMigration_Fase1_v1.0_GPO.ps1
      Parameters: -Password "YourP@ss123" -RemoveVMwareTools

    Tested on:
    - Windows Server 2012 R2 (PowerShell 3.0/4.0)
    - Windows Server 2016 (PowerShell 5.1)
    - Windows Server 2019 (PowerShell 5.1)
    - Windows Server 2022 (PowerShell 5.1)

.EXAMPLE
    # GPO deployment with all options
    .\Windows_PreMigration_Fase1_v1.0_GPO.ps1 -Password "MyP@ss123" -RemoveVMwareTools

.EXAMPLE
    # Network backup and user creation only (no VMware Tools removal)
    .\Windows_PreMigration_Fase1_v1.0_GPO.ps1 -Password "MyP@ss123"

.EXAMPLE
    # Full run with shutdown after completion
    .\Windows_PreMigration_Fase1_v1.0_GPO.ps1 -Password "MyP@ss123" -RemoveVMwareTools -ShutdownAfter
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Password,

    [switch]$RemoveVMwareTools,

    [switch]$ShutdownAfter,

    [string]$MigrationUser = "migrationadmin",

    [string]$WorkingDir = "C:\Migration"
)

# ============================================================
# CONFIGURATION
# ============================================================
$BackupFile = Join-Path $WorkingDir "network_backup.xml"
$LogFile    = Join-Path $WorkingDir "PreMigration_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# ============================================================
# LOGGING FUNCTION
# ============================================================
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry  = "$timestamp [$Level] $Message"
    Add-Content -Path $LogFile -Value $logEntry -ErrorAction SilentlyContinue

    # Also write to console if running interactively (for testing)
    switch ($Level) {
        "ERROR"   { Write-Host $logEntry -ForegroundColor Red -ErrorAction SilentlyContinue }
        "WARN"    { Write-Host $logEntry -ForegroundColor Yellow -ErrorAction SilentlyContinue }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green -ErrorAction SilentlyContinue }
        default   { Write-Host $logEntry -ErrorAction SilentlyContinue }
    }
}

# ============================================================
# EXECUTION
# ============================================================

# --- Phase 0: Administrator Check ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # Cannot use Write-Log yet (directory may not exist)
    Write-Error "This script must be run with Administrator privileges."
    exit 1
}

# Ensure the working directory exists
if (-not (Test-Path $WorkingDir)) {
    New-Item -ItemType Directory -Path $WorkingDir -Force | Out-Null
}

Write-Log "============================================================"
Write-Log "Windows VM Pre-Migration Script (GPO Edition) v1.0"
Write-Log "Computer: $($env:COMPUTERNAME)"
Write-Log "============================================================"

# ============================================================
# Phase 1: Network Configuration Backup
# ============================================================
Write-Log "--- Phase 1: Backing up network configuration ---"

try {
    if ($PSVersionTable.PSVersion.Major -ge 4) {
        # --- MODERN CODE PATH (PowerShell 4.0+) ---
        Write-Log "Modern PowerShell (v$($PSVersionTable.PSVersion.Major)) detected. Using Get-NetAdapter."

        $activeAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
        if (-not $activeAdapters) {
            Write-Log "No active network adapters found." "WARN"
        } else {
            $networkConfigurations = foreach ($adapter in $activeAdapters) {
                Write-Log "Processing adapter: '$($adapter.Name)'"
                $ipConfig = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex
                [PSCustomObject]@{
                    OriginalName   = $adapter.Name
                    InterfaceIndex = $adapter.ifIndex
                    MACAddress     = $adapter.MacAddress
                    IPAddresses    = $ipConfig.IPv4Address | ForEach-Object {
                        [PSCustomObject]@{
                            IPAddress    = $_.IPAddress
                            PrefixLength = $_.PrefixLength
                        }
                    }
                    DefaultGateway = $ipConfig.IPv4DefaultGateway.NextHop
                    DNSServers     = $ipConfig.DNSServer.ServerAddresses | Where-Object { $_ -match '^\d{1,3}\.' }
                }
            }
            $networkConfigurations | Export-CliXml -Path $BackupFile
            Write-Log "Network backup saved to '$BackupFile'." "SUCCESS"
        }
    }
    else {
        # --- LEGACY CODE PATH (PowerShell 3.0 and earlier) ---
        Write-Log "Legacy PowerShell (v$($PSVersionTable.PSVersion.Major)) detected. Using WMI."

        $ipEnabledConfigs = Get-WmiObject -Class Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }
        if (-not $ipEnabledConfigs) {
            Write-Log "No IP-enabled network adapters found." "WARN"
        } else {
            $networkConfigurations = foreach ($config in $ipEnabledConfigs) {
                $adapter = Get-WmiObject -Class Win32_NetworkAdapter | Where-Object { $_.Index -eq $config.Index }
                Write-Log "Processing adapter: '$($adapter.Name)'"

                $ipAddresses = for ($i = 0; $i -lt $config.IPAddress.Count; $i++) {
                    [PSCustomObject]@{
                        IPAddress    = $config.IPAddress[$i]
                        PrefixLength = (($(([System.Net.IPAddress]$config.IPSubnet[$i]).GetAddressBytes() | ForEach-Object { [convert]::ToString($_, 2).PadLeft(8, '0') } | Out-String).Replace("`r`n", "").ToCharArray() | Where-Object {$_ -eq '1' }) | Measure-Object).Count
                    }
                }

                [PSCustomObject]@{
                    OriginalName   = $adapter.Name
                    InterfaceIndex = $adapter.Index
                    MACAddress     = $adapter.MACAddress
                    IPAddresses    = $ipAddresses
                    DefaultGateway = $config.DefaultIPGateway
                    DNSServers     = $config.DNSServerSearchOrder | Where-Object { $_ -ne $null }
                }
            }
            $networkConfigurations | Export-CliXml -Path $BackupFile
            Write-Log "Network backup saved to '$BackupFile'." "SUCCESS"
        }
    }
} catch {
    Write-Log "Error during network backup: $($_.Exception.Message)" "ERROR"
}

# ============================================================
# Phase 2: Create Local Administrator Account
# ============================================================
Write-Log "--- Phase 2: Creating local user '$MigrationUser' ---"

try {
    $userExists = $false
    if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
        $userExists = [bool](Get-LocalUser -Name $MigrationUser -ErrorAction SilentlyContinue)
    } else {
        $userCheck = net user $MigrationUser 2>&1
        $userExists = ($LASTEXITCODE -eq 0)
    }

    if ($userExists) {
        Write-Log "User '$MigrationUser' already exists. Skipping." "WARN"
    } else {
        if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
            # Modern Path (PS 5.1+)
            $passwordSecure = ConvertTo-SecureString $Password -AsPlainText -Force
            New-LocalUser -Name $MigrationUser -Password $passwordSecure -FullName "Migration User" -Description "Temporary account for migration process."
            Add-LocalGroupMember -Group "Administrators" -Member $MigrationUser
            Write-Log "User '$MigrationUser' created and added to Administrators (Modern Method)." "SUCCESS"

            # Clear secure string
            Remove-Variable passwordSecure -ErrorAction SilentlyContinue
        } else {
            # Legacy Path (PS 3.0)
            net user $MigrationUser $Password /add /fullname:"Migration User" /comment:"Temporary account for migration process."
            net localgroup "Administrators" $MigrationUser /add
            Write-Log "User '$MigrationUser' created and added to Administrators (Legacy Method)." "SUCCESS"
        }
    }
} catch {
    Write-Log "Error creating local user: $($_.Exception.Message)" "ERROR"
}

# ============================================================
# Phase 3: Uninstall VMware Tools (if requested)
# ============================================================
Write-Log "--- Phase 3: VMware Tools check ---"

try {
    if ($RemoveVMwareTools) {
        Write-Log "VMware Tools removal requested. Searching..."

        $vmwareTools = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "VMware Tools" }

        if ($vmwareTools) {
            Write-Log "VMware Tools found: '$($vmwareTools.Name)' ($($vmwareTools.Version)). Uninstalling silently..."

            $msiArgs = "/X $($vmwareTools.IdentifyingNumber) /quiet /norestart"
            $uninstallResult = Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru

            if ($uninstallResult.ExitCode -in @(0, 3010)) {
                Write-Log "VMware Tools uninstalled successfully (exit code: $($uninstallResult.ExitCode))." "SUCCESS"
                if ($uninstallResult.ExitCode -eq 3010) {
                    Write-Log "A reboot is required to complete VMware Tools removal." "WARN"
                }
            } else {
                Write-Log "VMware Tools uninstall may have failed (exit code: $($uninstallResult.ExitCode))." "ERROR"
            }
        } else {
            Write-Log "VMware Tools not found. Nothing to remove." "SUCCESS"
        }
    } else {
        Write-Log "VMware Tools removal not requested. Skipping."
    }
} catch {
    Write-Log "Error during VMware Tools uninstall: $($_.Exception.Message)" "ERROR"
}

# ============================================================
# Phase 4: Shutdown (if requested)
# ============================================================
Write-Log "--- Phase 4: Completion ---"

Write-Log "============================================================"
Write-Log "Pre-migration completed for $($env:COMPUTERNAME)"
Write-Log "Log file: $LogFile"
Write-Log "Network backup: $BackupFile"
Write-Log "============================================================"

if ($ShutdownAfter) {
    Write-Log "Shutdown requested. VM will shut down in 30 seconds..." "WARN"
    Start-Sleep -Seconds 30
    Stop-Computer -Force
} else {
    Write-Log "Script complete. VM is ready for migration." "SUCCESS"
}

exit 0
