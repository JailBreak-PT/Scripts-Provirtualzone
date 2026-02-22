# Scripts-Provirtualzone

## Changelog

### 22/02/2026
Updated the Windows migration scripts to **v3.5** with English translations and sanitized for public sharing. All customer-specific data (paths, server names, domains, credentials) has been removed.

Updated scripts:
* `Windows_PreMigration_Fase1_v3.5.ps1` — Pre-migration: network backup, local admin creation (with visible password prompt), VMware Tools removal.
* `Windows_PostMigration_Fase2_v3.5.ps1` — Post-migration: network restore via MAC matching, IPv6 disable, data disk validation and drive letter fix.

Key improvements in v3.5:
* Dual-path compatibility: modern cmdlets (PS 4.0+) with automatic fallback to WMI/netsh/diskpart (PS 3.0).
* Tested on Windows Server 2012 R2, 2016, 2019, and 2022.
* No external dependencies — runs with built-in PowerShell cmdlets only.
* Designed for restricted enterprise environments (no internet, no installs, PowerShell ISE).
* Updated README with workflow diagram, compatibility matrix, and detailed documentation.

### 07/09/2025
Added a complete and robust toolchain for the automated migration of Linux VMs from VMware to Hyper-V. This new suite, located in the "Linux migrations script" folder, provides a full end-to-end workflow.

Key features include:
* Pre-migration preparation (network backup, VMware Tools removal, safe GRUB modification).
* Post-migration validation with an interactive cleanup option.
* Universal compatibility across major distributions (RHEL, CentOS, Oracle Linux, Debian) and versions (e.g., EL6 to EL9).
* A PowerShell front-end for automating key deployment and remote execution.

### 05/09/2025
Added two folders in the Migration script section. One for the Windows migrations script and one for the Linux migrations script.

### 31/08/2025
Added new script PostCutover_Network_Sanity.ps1 with some changes in case the VM still has the VMware tools installed in the VM. It will request to remove the VMware tools and then reboot.
