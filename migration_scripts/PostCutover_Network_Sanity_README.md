# PostCutover_Network_Sanity.ps1

Clean up Windows VMs after migrating off VMware while keeping IP settings intact.  
Removes only nonpresent VMware NICs.  
Optional VMware driver package cleanup.  
Backups and logs before risky actions.  
Built-in restore for drivers and saved IPs.

## Why use it

- You migrated a VM from VMware to Hyper-V, Proxmox, or other.
- You want a clean device list without breaking networking.
- You need backups, logs, and a restore path.

## Key features

- Preserves IP, DNS, gateway, and routes by default.
- Removes only nonpresent VMware NICs.
- Optional removal of VMware-named DriverStore packages.
- Backups and logs before changes.
- Built-in restore for drivers and, if you want, IPs.
- Color output with clear levels. Disable with `-NoColor`.

## Requirements

- Windows PowerShell 5.1 or newer.
- Run as Administrator.
- Copy the script into the VM before cutover.

## Safety rules

- If VMware Tools is installed, the script offers to uninstall, then stops. Reboot and run again.
- If the VM is on VMware, the script warns and asks twice before continuing.
- No TCP/IP reset. No `netcfg -d`.
- No registry edits except when steps target clearly VMware-named items. Default path does not touch registry.

## Quick start

```powershell
# Fast cleanup with backups
.\PostCutover_Network_Sanity.ps1 -Cleanup

# Cleanup plus remove VMware driver packages
.\PostCutover_Network_Sanity.ps1 -Cleanup -RemoveDriverStore

# DNS cache only
.\PostCutover_Network_Sanity.ps1 -FlushDns

# Winsock only (reboot recommended)
.\PostCutover_Network_Sanity.ps1 -WinsockReset

# Dry run
.\PostCutover_Network_Sanity.ps1 -Cleanup -WhatIf
