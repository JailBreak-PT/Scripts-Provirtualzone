# Windows Pre & Post Migration Scripts

Two PowerShell scripts that handle the **before** and **after** of a VMware to Hyper-V migration. They work as a pair — Phase 1 captures the VM state, Phase 2 restores it on the new platform.

- **Dual-Path Compatibility:** Automatically detects PowerShell version and uses modern cmdlets (PS 4.0+) or legacy fallback (WMI, netsh, diskpart) for PS 3.0.
- **No Dependencies:** Uses only built-in Windows cmdlets. No internet, no modules, no installs required.
- **Enterprise Ready:** Designed for restricted environments running PowerShell ISE as Administrator.
- **Tested on:** Windows Server 2012 R2, 2016, 2019, and 2022.

---

## Scripts

| Script | Phase | Purpose |
|--------|-------|---------|
| `Windows_PreMigration_Fase1_v3.5.ps1` | **Before** migration | Backup network, create migration user, remove VMware Tools |
| `Windows_PostMigration_Fase2_v3.5.ps1` | **After** migration | Restore network, disable IPv6, validate and fix data disks |

---

## Quick Start

### Phase 1: Pre-Migration (run on the VMware VM)

1. Copy `Windows_PreMigration_Fase1_v3.5.ps1` to the VM
2. Open **PowerShell ISE** as Administrator
3. Edit the configuration block at the top:
   ```powershell
   $workingDir    = "C:\Migration"        # Where to save backup files
   $migrationUser = "migrationadmin"      # Local admin account name
   ```
4. Run the script (F5)

### Phase 2: Post-Migration (run on the Hyper-V VM)

1. Copy `Windows_PostMigration_Fase2_v3.5.ps1` to the VM
2. Make sure the network backup XML from Phase 1 is in the same path
3. Open **PowerShell ISE** as Administrator
4. Edit the configuration block:
   ```powershell
   $workingDir = "C:\Migration"           # Must match the Phase 1 path
   ```
5. Run the script (F5)

> **Important:** The `$workingDir` path must be the same in both scripts. Phase 2 reads the backup file created by Phase 1.

---

## What Each Script Does

### Phase 1 — Pre-Migration

| Step | Action | Description |
|------|--------|-------------|
| 1 | **Network Backup** | Exports full network config (IP, DNS, Gateway, MAC) to XML |
| 2 | **Create Migration User** | Creates a local administrator account with visible password prompt |
| 3 | **Uninstall VMware Tools** | Optionally removes VMware Tools with user confirmation |
| 4 | **Shutdown** | Optional VM shutdown (commented out by default) |

### Phase 2 — Post-Migration

| Step | Action | Description |
|------|--------|-------------|
| 1 | **Import Backup** | Reads the network backup XML created by Phase 1 |
| 2 | **Restore Network** | Matches adapters by MAC address, restores IP/DNS/Gateway, renames adapters to original names |
| 3 | **Disable IPv6** | Disables IPv6 on all adapters (modern cmdlets or registry fallback) |
| 4 | **Fix Data Disks** | Brings disks online, removes read-only, fixes drive letters |

---

## Phase 2 — Disk Handling Details

The post-migration disk validation handles several common issues after a V2V migration:

- **CD/DVD on D:** — Automatically moves CD/DVD drive from D: to Z: to free up the letter for data disks.
- **Offline disks** — Brings all data disks online and removes read-only flags.
- **Drive letter D:** — Assigns D: to the largest partition on Disk 1 (common for data drives).
- **Orphaned mount points** — Cleans up via CIM, Storage module, diskpart, and mountvol.
- **No Disk 1** — Safely skips all Disk 1 operations if the system only has an OS disk.
- **Dual-path execution** — Uses Storage module when available, falls back to diskpart/CIM for older systems.

---

## Security Notes

### Phase 1 — Password Handling
- Password input is **visible** on screen during typing (by design, for restricted environments).
- Password is displayed on screen after confirmation for verification.
- Password is **NOT logged** to any file or transcript.
- Password variables are cleared from memory after user creation.
- The migration account should be removed after migration is complete.

### Phase 2 — No Credentials
- Network configuration is restored from the XML backup — no credentials are stored or needed.
- All operations use built-in Windows cmdlets with no external calls.

---

## What To Run Next

After Phase 2, run the cleanup scripts to remove ghost VMware devices:

→ See `README_Hidden_Devices_Remove.md` for `Hidden_Devices_Remove_Total_v3_0.ps1`

---

## License

MIT

## Maintainer

Luciano Patrão
