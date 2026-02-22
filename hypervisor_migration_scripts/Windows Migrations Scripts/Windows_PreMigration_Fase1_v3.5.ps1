<#
.SYNOPSIS
    Universal Pre-Migration Script for Windows VMs (VMware to Hyper-V).
    Version 3.5

.DESCRIPTION
    This script prepares a Windows VM for migration from VMware to Hyper-V.
    It automatically detects the PowerShell version and uses the appropriate
    cmdlets for maximum compatibility (PS v3 through v5.1+).

    What it does:
    - Phase 1: Backs up the current network configuration (IP, DNS, Gateway, MAC)
    - Phase 2: Creates a local administrator account for migration purposes
    - Phase 3: Optionally uninstalls VMware Tools
    - Phase 4: (Optional) Shuts down the VM for migration

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

.EXAMPLE
    # Run in PowerShell ISE as Administrator
    .\Windows_PreMigration_Fase1_v3.5.ps1
#>

# ============================================================
# CONFIGURATION - Adjust these settings for your environment
# ============================================================
$workingDir    = "C:\Migration"                # Working directory for backup files
$BackupFile    = Join-Path $workingDir "network_backup.xml"
$migrationUser = "migrationadmin"              # Name of the local admin account to create

# ============================================================
# EXECUTION - Do not modify below this line
# ============================================================

# --- Phase 0: Administrator Check ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run with Administrator privileges. Please open PowerShell as Administrator and try again."
    exit 1
}

# Ensure the working directory exists
if (-not (Test-Path $workingDir)) {
    New-Item -ItemType Directory -Path $workingDir -Force | Out-Null
}

Clear-Host
Write-Host "============================================================"
Write-Host "  Windows VM Pre-Migration Script (VMware to Hyper-V)"
Write-Host "  Version 3.5"
Write-Host "============================================================"
Write-Host ""

# ============================================================
# Phase 1: Network Configuration Backup
# ============================================================
Write-Host "--- Phase 1: Backing up network configuration ---" -ForegroundColor Cyan

# Detect PowerShell version to choose the right code path
if ($PSVersionTable.PSVersion.Major -ge 4) {
    # --- MODERN CODE PATH (PowerShell 4.0+) ---
    Write-Host "  > Modern PowerShell (v4+) detected. Using Get-NetAdapter."
    try {
        $activeAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
        if (-not $activeAdapters) {
            Write-Warning "No active network adapters found."
        } else {
            $networkConfigurations = foreach ($adapter in $activeAdapters) {
                Write-Host "  > Processing adapter: '$($adapter.Name)'"
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
            Write-Host "  > Network backup saved to '$BackupFile'." -ForegroundColor Green
        }
    } catch {
        Write-Error "Error during network backup: $($_.Exception.Message)"
    }
}
else {
    # --- LEGACY CODE PATH (PowerShell 3.0 and earlier) ---
    Write-Host "  > Legacy PowerShell (v3 or earlier) detected. Using WMI."
    try {
        $ipEnabledConfigs = Get-WmiObject -Class Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }
        if (-not $ipEnabledConfigs) {
            Write-Warning "No IP-enabled network adapters found."
        } else {
            $networkConfigurations = foreach ($config in $ipEnabledConfigs) {
                $adapter = Get-WmiObject -Class Win32_NetworkAdapter | Where-Object { $_.Index -eq $config.Index }
                Write-Host "  > Processing adapter: '$($adapter.Name)'"

                $ipAddresses = for ($i = 0; $i -lt $config.IPAddress.Count; $i++) {
                    [PSCustomObject]@{
                        IPAddress    = $config.IPAddress[$i]
                        # Convert subnet mask to CIDR prefix length (compatible with PSv3)
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
            Write-Host "  > Network backup saved to '$BackupFile'." -ForegroundColor Green
        }
    } catch {
        Write-Error "Error during network backup: $($_.Exception.Message)"
    }
}

# ============================================================
# Phase 2: Create Local Administrator Account
# ============================================================
Write-Host "`n--- Phase 2: Creating local user '$migrationUser' ---" -ForegroundColor Cyan
try {
    # Detect if user already exists (compatible method)
    $userExists = $false
    if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
        $userExists = [bool](Get-LocalUser -Name $migrationUser -ErrorAction SilentlyContinue)
    } else {
        $userCheck = net user $migrationUser 2>&1
        $userExists = ($LASTEXITCODE -eq 0)
    }

    # If user exists, skip. If not, create them.
    if ($userExists) {
        Write-Host "  > User '$migrationUser' already exists. No action needed." -ForegroundColor Yellow
    } else {
        Write-Host "  > User '$migrationUser' not found. Proceeding with creation..."

        # --- Password Prompt Block (Visible Input) ---
        $passwordText = $null

        # Loop until passwords match
        while ($true) {
            $passwordText    = Read-Host -Prompt "  > Enter new password for '$migrationUser'"
            $passwordConfirm = Read-Host -Prompt "  > Confirm new password"

            if ($passwordText -eq $passwordConfirm) {
                Write-Host "  > Password confirmed: $passwordText" -ForegroundColor Green
                $passwordConfirm = $null
                break
            } else {
                Write-Warning "Passwords do not match. Please try again."
            }
        }
        # --- End Password Prompt Block ---

        # Create the user using the appropriate method
        if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
            # Modern Path (PS 5.1+): Convert to SecureString for New-LocalUser
            $passwordSecure = ConvertTo-SecureString $passwordText -AsPlainText -Force
            New-LocalUser -Name $migrationUser -Password $passwordSecure -FullName "Migration User" -Description "Temporary account for migration process."
            Add-LocalGroupMember -Group "Administrators" -Member $migrationUser
            Write-Host "  > User '$migrationUser' created and added to Administrators group (Modern Method)." -ForegroundColor Green
        } else {
            # Legacy Path (PS 3.0): Use net user command
            net user $migrationUser $passwordText /add /fullname:"Migration User" /comment:"Temporary account for migration process."
            net localgroup "Administrators" $migrationUser /add
            Write-Host "  > User '$migrationUser' created and added to Administrators group (Legacy Method)." -ForegroundColor Green
        }

        # Clear password variables from memory
        if ($passwordText)   { Remove-Variable passwordText -ErrorAction SilentlyContinue }
        if ($passwordSecure) { Remove-Variable passwordSecure -ErrorAction SilentlyContinue }
    }
} catch {
    Write-Error "An error occurred while creating the local user: $($_.Exception.Message)"
}

# ============================================================
# Phase 3: Uninstall VMware Tools
# ============================================================
Write-Host "`n--- Phase 3: Uninstalling VMware Tools ---" -ForegroundColor Cyan
try {
    # Get-WmiObject is compatible with all PowerShell versions
    $vmwareTools = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "VMware Tools" }

    if ($vmwareTools) {
        $choice = Read-Host -Prompt "VMware Tools found. Do you want to uninstall them now? (yes/no)"

        if ($choice -like 'y*') {
            Write-Host "  > Uninstalling as requested..."

            $msiArgs = "/X $($vmwareTools.IdentifyingNumber) /quiet /norestart"
            $uninstallResult = Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru

            if ($uninstallResult.ExitCode -in @(0, 3010)) {
                Write-Host "  > VMware Tools uninstall completed successfully." -ForegroundColor Green
            } else {
                Write-Warning "VMware Tools uninstall may have failed with exit code: $($uninstallResult.ExitCode)"
            }
        }
        else {
            Write-Host "  > Skipping VMware Tools uninstallation as requested." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  > VMware Tools not found. No action needed." -ForegroundColor Yellow
    }
} catch {
    Write-Error "An error occurred during VMware Tools uninstall: $($_.Exception.Message)"
}

# ============================================================
# Phase 4: Shutdown (Optional)
# ============================================================
Write-Host "`n--- Pre-migration process completed ---" -ForegroundColor Cyan
Write-Host "The VM is ready to be migrated."
# To shut down the VM automatically, uncomment the lines below:
# Write-Host "The VM will shut down in 30 seconds..." -ForegroundColor Yellow
# Start-Sleep -Seconds 30
# Stop-Computer -Force
