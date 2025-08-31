# PostCutover_Network_Sanity.ps1

Clean Windows VMs after migrating off VMware without breaking networking.

- Removes only nonpresent VMware NICs
- Optional cleanup of VMware-named DriverStore packages
- Backups and logs before risky actions
- Built-in restore for drivers and IPs (opt-in)
- Color output with clear levels (use `-NoColor` to disable)

## Why use it

- You migrated a VM from VMware to Hyper-V, Proxmox, or another hypervisor.
- You want a clean device list and stable networking.
- You need a reversible, auditable process.

## Requirements

- Windows PowerShell 5.1+
- Run as Administrator
- Copy the script into the VM **before** cutover

## Safety rules

- If the VM is running on VMware, the script warns and asks twice before continuing.
- If VMware Tools is installed, the script offers to uninstall it, then stops. Reboot and run again.
- No TCP/IP reset. No `netcfg -d`.
- No registry edits except when steps target clearly VMware‑named items. Default path does not touch registry.

## Quick start

```powershell
# Fast cleanup with backups
.\PostCutover_Network_Sanity.ps1 -Cleanup

# Cleanup + remove VMware driver packages
.\PostCutover_Network_Sanity.ps1 -Cleanup -RemoveDriverStore

# DNS cache only
.\PostCutover_Network_Sanity.ps1 -FlushDns

# Winsock only (reboot recommended)
.\PostCutover_Network_Sanity.ps1 -WinsockReset

# Dry run (no changes)
.\PostCutover_Network_Sanity.ps1 -Cleanup -WhatIf
```

## Parameters

- `-Cleanup` remove nonpresent VMware NICs. Creates a backup first.
- `-RemoveDriverStore` remove VMware‑named DriverStore packages. Creates a backup first.
- `-FlushDns` flush DNS cache only.
- `-WinsockReset` reset Winsock only. Reboot recommended.
- `-Restore` restore drivers from the latest backup or `-BackupPath`.
- `-RestoreIP` with `-Restore`, reapply saved IPs by MAC or alias.
- `-BackupPath <folder>` use a specific `C:\PostMig\Backups\YYYYMMDD_HHMMSS` path.
- `-NoColor` disable colored console output.
- `-WhatIf` show actions without changing anything.

## Output

Backups
- `C:\PostMig\Backups\YYYYMMDD_HHMMSS\Drivers\` DriverStore export
- `C:\PostMig\Backups\YYYYMMDD_HHMMSS\DeviceInventory.csv`
- `C:\PostMig\Backups\YYYYMMDD_HHMMSS\IPConfig.csv`
- `C:\PostMig\Backups\YYYYMMDD_HHMMSS\IPConfig.json`

Logs
- `C:\PostMig\Logs\PostCutover_Network_Sanity_YYYYMMDD_HHMMSS.log`

## Restore

```powershell
# Restore drivers from the latest backup
.\PostCutover_Network_Sanity.ps1 -Restore

# Restore drivers and saved IPs
.\PostCutover_Network_Sanity.ps1 -Restore -RestoreIP

# Restore from a specific backup
.\PostCutover_Network_Sanity.ps1 -Restore -BackupPath C:\PostMig\Backups50831_120000
```

## Validation checklist

- No VMware ghost NICs in Device Manager
- `pnputil /enum-drivers` has no vmxnet/pvscsi/vmci packages (if removed)
- `vssadmin list providers` shows only Microsoft (if you removed VMware provider elsewhere)
- IP, DNS, gateway unchanged on the active NIC
- Log shows clean completion

## Notes

- Run on the first boot after cutover.
- Prefer console access on first run.
- Keep `Hidden_Devices_Remove.ps1` if you want a quick, single-purpose cleanup.
- This script adds backups, restore, and a clearer operator experience.

## License

MIT

## Maintainer

Luciano Patrao
