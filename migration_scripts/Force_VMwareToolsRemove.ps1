# =====================================================================================
# Name:    Force-RemoveVMwareTools.ps1
# Author:  Luciano Patrao
# Version: 1.3
# Date: 31/08/2025
#
# Purpose: Forcefully removes a corrupted VMware Tools installation when standard
#          uninstall methods have failed. USE AS A LAST RESORT.
#
# Usage:   Run as Administrator. A reboot is required immediately after.
# =====================================================================================

Clear-Host

# --- Administrator Check and Final Confirmation ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run with Administrator privileges."
    Start-Sleep -Seconds 5
    exit 1
}

Write-Host "========================== WARNING ==========================" -ForegroundColor Red
Write-Host "This script will forcefully remove VMware Tools from this system." -ForegroundColor Yellow
Write-Host "This should only be used if the normal uninstaller is broken." -ForegroundColor Yellow
Write-Host "A system reboot is REQUIRED after this script completes." -ForegroundColor Yellow
Write-Host "===========================================================" -ForegroundColor Red
Write-Host ""

$confirmation = Read-Host "Type 'YES' to proceed with the forceful removal"
if ($confirmation -ne 'YES') {
    Write-Host "Confirmation not received. Aborting script." -ForegroundColor Green
    Start-Sleep -Seconds 3
    exit
}

Clear-Host
Write-Host "Proceeding with forceful removal..." -ForegroundColor Cyan

# --- Step 1: Stopping and Deleting VMware Services ---
Write-Host "`n--- Step 1: Stopping and Deleting VMware Services ---" -ForegroundColor Cyan
$vmwareServices = @(
    'VMTools',
    'VGAuthService',
    'VMware Physical Disk Helper Service',
    'VMUSBArbService',
    'VMwareCAFManagementAgentHost'
)

foreach ($service in $vmwareServices) {
    Write-Host " > Targeting service: $service"
    Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
    try {
        $serviceObject = Get-Service -Name $service -ErrorAction SilentlyContinue
        if ($serviceObject) {
            Write-Host "   - Deleting service..."
            sc.exe delete $service | Out-Null
        }
    }
    catch {
        Write-Warning "   - Could not delete service '$service'. It may not exist."
    }
}

# --- Step 2: Terminating VMware Processes ---
Write-Host "`n--- Step 2: Terminating VMware Processes ---" -ForegroundColor Cyan
$vmwareProcesses = @(
    'vmtoolsd',
    'vmacthlp',
    'VGAuthService'
)
foreach ($process in $vmwareProcesses) {
    Write-Host " > Terminating process: $process"
    Stop-Process -Name $process -Force -ErrorAction SilentlyContinue
}

# --- Step 3: Purging VMware Drivers from the Driver Store ---
Write-Host "`n--- Step 3: Purging VMware Drivers ---" -ForegroundColor Cyan
$oemSet = @()
$current = @{}
pnputil.exe /enum-drivers | ForEach-Object {
    if ($_ -match 'Published Name\s*:\s*(oem\d+\.inf)') { $current['Name'] = $Matches[1] }
    elseif ($_ -match 'Provider Name\s*:\s*(.*)') { $current['Provider'] = $Matches[1].Trim() }
    elseif ($_ -match 'Driver Name\s*:\s*(.*)') {
        $current['Driver'] = $Matches[1].Trim()
        if ($current['Name']) { $oemSet += [pscustomobject]$current; $current = @{} }
    }
}
$vmwOems = $oemSet | Where-Object { $_.Provider -match 'VMware' }
if ($vmwOems) {
    foreach ($oem in $vmwOems) {
        Write-Host " > Deleting driver package: $($oem.Name) ($($oem.Driver))"
        pnputil.exe /delete-driver $oem.Name /uninstall /force | Out-Null
    }
} else {
    Write-Host " > No VMware driver packages found in the Driver Store."
}

# --- Step 4: Deleting VMware Tools Files and Folders ---
Write-Host "`n--- Step 4: Deleting VMware Tools Files and Folders ---" -ForegroundColor Cyan
$vmwarePaths = @(
    "$env:ProgramFiles\VMware\VMware Tools",
    "$env:ProgramData\VMware\VMware Tools"
)
foreach ($path in $vmwarePaths) {
    if (Test-Path $path) {
        Write-Host " > Deleting path: $path"
        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Step 5: Scrubbing Registry ---
Write-Host "`n--- Step 5: Scrubbing Registry ---" -ForegroundColor Cyan
$registryPaths = @(
    'HKLM:\SOFTWARE\VMware, Inc.\VMware Tools',
    'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMware Tools'
)
# Find and remove the Uninstall key
$uninstallKeyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
$vmwUninstallKey = Get-ChildItem -Path $uninstallKeyPath -ErrorAction SilentlyContinue | ForEach-Object {
    $displayName = Get-ItemProperty -Path $_.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty "DisplayName"
    if ($displayName -like "VMware Tools*") {
        return $_.PSPath
    }
}
if ($vmwUninstallKey) {
    $registryPaths += $vmwUninstallKey
}

foreach ($regPath in $registryPaths) {
    if (Test-Path $regPath) {
        Write-Host " > Deleting registry key: $regPath"
        Remove-Item -Path $regPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Step 6: Final Instructions ---
Write-Host "`n======================= COMPLETE =======================" -ForegroundColor Green
Write-Host "Forceful removal attempt finished."
Write-Host "A SYSTEM REBOOT IS REQUIRED to complete the process." -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Green
