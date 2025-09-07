# PostCutover\_Network\_Sanity.ps1

A robust, safe, and automated PowerShell script to clean Windows Guest OS VMs after migrating off VMware to Hyper-V, Proxmox, or another hypervisor.

  - **Runs all cleanup tasks by default** (no parameters needed).
  - **Performs a pre-scan** and exits if the system is already clean.
  - **Cleans ALL non-present VMware devices** (NICs, disks, mouse, etc.) using a proven, pattern-based search.
  - **Forcefully removes corrupted VMware Tools** when the standard uninstaller fails (interactive).
  - Optionally cleans up VMware-named DriverStore packages.
  - Creates comprehensive **backups and detailed logs** before any changes are made.
  - Includes a built-in **restore function** for drivers and IP configurations.
  - Provides clear, color-coded output (can be disabled with `-NoColor`).

## Why use it

  - You migrated a VM from VMware to Hyper-V, Proxmox, or another hypervisor.
  - You want a clean device list and stable networking.
  - You need a reversible, auditable, and highly automated process.

## Requirements

  - Windows PowerShell 5.1+
  - Run as Administrator
  - It is recommended to copy the script into the VM **before** the final cutover for convenience.

## Safety rules

  - If the script detects it's running on a **VMware** platform, it will warn you and require multiple confirmations before proceeding.
  - If **VMware Tools** is still installed, the script will first offer to run the standard uninstaller. If that fails, it will then offer to perform a more aggressive, forceful removal as a last resort. The script will stop after any uninstall attempt, requiring a reboot.
  - The script does not perform destructive network resets **by default**. Actions like `-WinsockReset` are strictly opt-in.
  - The main cleanup path for devices and drivers does not modify the registry. The **forceful VMware Tools removal** option is an exception and will remove specific VMware registry keys as a last resort.

## Quick start

```powershell
# Run ALL cleanup tasks automatically (Default)
# This finds and removes devices, cleans the DriverStore, flushes DNS, and resets Winsock.
.\PostCutover_Network_Sanity.ps1

# To run ONLY the device cleanup
.\PostCutover_Network_Sanity.ps1 -CleanupDevices

# Dry run: Show what would be cleaned without making changes
.\PostCutover_Network_Sanity.ps1 -WhatIf
```

## Parameters

  - **Default (No Parameters)**: Runs all cleanup tasks in sequence: `CleanupDevices`, `RemoveDriverStore`, `FlushDns`, and `WinsockReset`.
  - `-CleanupDevices`: Removes **ALL** non-present VMware devices found using pattern matching. Creates a backup first.
  - `-RemoveDriverStore`: Removes VMware‑named DriverStore packages. Creates a backup first.
  - `-FlushDns`: Flushes the DNS cache only.
  - `-WinsockReset`: Resets Winsock only. A reboot is recommended.
  - `-Restore`: Restores drivers from the latest backup or from the path specified with `-BackupPath`.
  - `-RestoreIP`: Used with `-Restore`, this will also reapply the saved IP configuration.
  - `-BackupPath <folder>`: Specifies a custom backup path to use for a restore operation.
  - `-NoColor`: Disables colored console output.
  - `-WhatIf`: Shows the actions the script would take without actually performing them.

## Output

### Backups

  - `C:\PostMig\Backups\YYYYMMDD_HHMMSS\Drivers\` (DriverStore export)
  - `C:\PostMig\Backups\YYYYMMDD_HHMMSS\DeviceInventory.csv`
  - (and other log files for specific operations)

### Logs

  - `C:\PostMig\Logs\PostCutover_Network_Sanity_YYYYMMDD_HHMMSS.log`

## Restore

```powershell
# Restore drivers from the latest backup
.\PostCutover_Network_Sanity.ps1 -Restore

# Restore drivers and the saved IP configuration
.\PostCutover_Network_Sanity.ps1 -Restore -RestoreIP

# Restore from a specific, older backup
.\PostCutover_Network_Sanity.ps1 -Restore -BackupPath C:\PostMig\Backups\YYYYMMDD_HHMMSS
```

## Validation checklist

  - No VMware ghost **devices** in Device Manager (check "Show hidden devices").
  - `pnputil /enum-drivers` has no vmxnet/pvscsi/vmci packages (if `-RemoveDriverStore` was used).
  - IP, DNS, and gateway are unchanged on the active NIC.
  - The log file in `C:\PostMig\Logs` shows a clean completion.

## Notes

  - For best results, run the script on the first boot after the migration is complete.
  - Using a direct console session (like Hyper-V's Virtual Machine Connection) is recommended for the first run.

## License

MIT

## Maintainer

Luciano Patrao
