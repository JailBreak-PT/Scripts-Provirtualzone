# =====================================================================================
# Name:    Hidden_Devices_Remove.ps1
# Author:  Luciano Patrao
# Version: 1.3
#
# Purpose: Cleans a Windows VM after migration by removing old, hidden ('ghost')
#          VMware hardware devices to prevent driver conflicts.
#
# USAGE:   Run as Administrator on the new VM (e.g., on Hyper-V) BEFORE
#          reconfiguring the network. A reboot is recommended after execution.
# =====================================================================================

Clear-Host

# 0. Check if the script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
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

Write-Host "============================================================"
Write-Host "--- Starting VMware Device Cleanup Script ---"
Write-Host "============================================================"


    $vmwareTools = Get-CimInstance -ClassName Win32_Product | Where-Object { $_.Name -like "VMware Tools" }
    if ($vmwareTools) {
        Write-Host "  > VMware Tools detected. Cannot continue..." -ForegroundColor Red
        exit 1
        }
     

# 1. Define the patterns of VMware device names to search for
$vmwareDevicePatterns = @(
    "*VMware*",                  # Catches most devices (SVGA, SCSI, etc.)
    "vmxnet3*",                 # Catches the VMXNET3 network adapter
    "Intel(R) 82574L*"          # Catches the E1000 network adapter commonly emulated by VMware
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
$devicesToRemove = $devicesToRemove | Sort-Object -Property InstanceId -Unique

# 3. Remove the found devices
if ($devicesToRemove) {
    Write-Host "`n[STEP 2/3] The following VMware devices will be removed:" -ForegroundColor Yellow
    $devicesToRemove | Format-Table @{N='Name';E={$_.FriendlyName}}, Class, Status, InstanceId -AutoSize
    
    Read-Host "Press Enter to continue with the removal..."

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
                 Write-Warning "  > Failed to remove the device. Exit Code: $($proc.ExitCode)"
            }
        }
    }

    Write-Host "`n[STEP 3/3] Re-scanning system hardware..." -ForegroundColor Cyan
    # Ask Windows to re-scan the device bus
    Start-Process -FilePath "pnputil.exe" -ArgumentList "/scan-devices" -Wait -NoNewWindow
    
} else {
    Write-Host "`n[INFO] No old VMware devices were found." -ForegroundColor Green
    Write-Host "`n[SUCCESS] The cleanup process is complete." -ForegroundColor Green
    exit 1
}

Write-Host "`n[SUCCESS] The cleanup process is complete." -ForegroundColor Green
Write-Host "It is recommended to restart the VM before reconfiguring the network."
