# Windows Migration Toolkit (VMware to Hyper-V)

A complete set of PowerShell scripts for migrating Windows VMs from VMware to Hyper-V (or Proxmox). Designed for **restricted enterprise environments** with no internet access and no ability to install additional software.

---

## Recommended Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│  1. BEFORE MIGRATION — Run on the VMware VM                     │
│     → Windows_PreMigration_Fase1_v3.5.ps1                       │
│       Backs up network, creates migration user, removes         │
│       VMware Tools                                              │
├─────────────────────────────────────────────────────────────────┤
│  2. MIGRATION                                                    │
│     → Perform V2V (SCVMM, StarWind, or other V2V tool)          │
├─────────────────────────────────────────────────────────────────┤
│  3. AFTER MIGRATION — Run on the Hyper-V VM                      │
│     → Windows_PostMigration_Fase2_v3.5.ps1                      │
│       Restores network (IP/DNS/Gateway), disables IPv6,          │
│       brings data disks online and fixes drive letters           │
├─────────────────────────────────────────────────────────────────┤
│  4. CLEANUP — Run on the Hyper-V VM                              │
│     → Hidden_Devices_Remove_Total_v3_0.ps1 (recommended)        │
│       Removes ghost VMware devices, cleans DriverStore,          │
│       flushes DNS, resets Winsock, backup & restore support      │
│                                                                  │
│     → Force_VMwareToolsRemove.ps1 (only if needed)              │
│       Last resort for corrupted VMware Tools that won't          │
│       uninstall through normal methods                           │
├─────────────────────────────────────────────────────────────────┤
│  5. REBOOT and validate                                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## Script Inventory

| Script | Purpose | Version |
|--------|---------|---------|
| `Windows_PreMigration_Fase1_v3.5.ps1` | Pre-migration: network backup, local admin creation, VMware Tools removal | v3.5 |
| `Windows_PostMigration_Fase2_v3.5.ps1` | Post-migration: network restore, IPv6 disable, data disk validation | v3.5 |
| `Hidden_Devices_Remove_Total_v3_0.ps1` | **Full cleanup toolkit** — ghost devices, DriverStore, DNS, Winsock, with `-Aggressive` mode | v3.0 |
| `Force_VMwareToolsRemove.ps1` | Last resort forceful VMware Tools removal (services, drivers, registry) | v1.0 |

### GPO Scripts (subfolder: `GPO Scripts/`)

| Script | Purpose | Version |
|--------|---------|---------|
| `Windows_PreMigration_Fase1_v1.0_GPO.ps1` | Unattended pre-migration for AD OU deployment via Group Policy | v1.0 |
| `README_GPO_Deployment.md` | Step-by-step GPO deployment guide | — |

---

## Compatibility

All scripts automatically detect the PowerShell version and use the appropriate cmdlets:

| Windows Server | PowerShell | Method |
|---------------|------------|--------|
| 2012 R2 | 3.0 / 4.0 | WMI, netsh, diskpart (legacy fallback) |
| 2016 | 5.1 | Modern cmdlets (NetAdapter, Storage) |
| 2019 | 5.1 | Modern cmdlets (NetAdapter, Storage) |
| 2022 | 5.1 | Modern cmdlets (NetAdapter, Storage) |

## Requirements

- Run as **Administrator** (PowerShell ISE recommended)
- No internet access required
- No external modules or dependencies
- Works with built-in Windows cmdlets only

---

## Documentation

Each script has its own detailed README:

| README | Covers |
|--------|--------|
| `README_PrePostMigration.md` | Pre-migration (Fase1) and Post-migration (Fase2) scripts |
| `README_VMwareToolsRemove.md` | Force VMware Tools Remove script |
| `GPO Scripts/README_GPO_Deployment.md` | GPO deployment guide for AD OU automation |

---

## Changelog

### 22/02/2026
Updated the Windows migration scripts to **v3.5**.

Updated scripts:
* `Windows_PreMigration_Fase1_v3.5.ps1` — Pre-migration: network backup, local admin creation (with visible password prompt), VMware Tools removal.
* `Windows_PostMigration_Fase2_v3.5.ps1` — Post-migration: network restore via MAC matching, IPv6 disable, data disk validation and drive letter fix.
* `GPO Scripts/Windows_PreMigration_Fase1_v1.0_GPO.ps1` — New unattended version of pre-migration for deployment via Group Policy to an AD OU.

Key improvements in v3.5:
* Dual-path compatibility: modern cmdlets (PS 4.0+) with automatic fallback to WMI/netsh/diskpart (PS 3.0).
* Tested on Windows Server 2012 R2, 2016, 2019, and 2022.
* No external dependencies — runs with built-in PowerShell cmdlets only.
* Designed for restricted enterprise environments (no internet, no installs, PowerShell ISE).

Other changes:
* Removed old superseded scripts (`Hidden_Devices_Remove.ps1` v1.3 and `PostCutover_Network_Sanity.ps1` v2.2) — replaced by `Hidden_Devices_Remove_Total_v3_0.ps1`.
* Removed `README_Hidden_Devices_Remove.md` and `README_PostCutover_Network_Sanity.md` — no longer needed.

### 19/09/2025
Released `Hidden_Devices_Remove_Total_v3_0.ps1` — the unified cleanup toolkit.
* Merged `Hidden_Devices_Remove.ps1` and `PostCutover_Network_Sanity.ps1` into a single script.
* Added new `-Aggressive` mode for forced removal of VMware services.
* Improved device search to use both Name patterns and Hardware ID (VEN_15AD).

### 31/08/2025
Added PostCutover_Network_Sanity.ps1 with some changes in case the VM still has the VMware tools installed in the VM. It will request to remove the VMware tools and then reboot.

## Disclaimer
USE AT YOUR OWN RISK. These scripts are provided "as is" without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement. In no event shall the author be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the scripts or the use or other dealings in the scripts.

Always test in a non-production environment before running on any production or critical infrastructure. The author assumes no responsibility for data loss, system downtime, misconfigurations, or any other issues that may arise from the use of these scripts. Every environment is different — it is the user's responsibility to review, understand, and validate the scripts before execution.
By using these scripts, you accept full responsibility for any outcomes.

---

## License

MIT

## Author

**Luciano Patrão**
