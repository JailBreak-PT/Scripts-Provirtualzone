# Windows Migration Scripts

## Last Update — 22/02/2026

### What Changed
- Added `Windows_PreMigration_Fase1_v3.5.ps1` — Pre-migration script (network backup, user creation, VMware Tools removal).
- Added `Windows_PostMigration_Fase2_v3.5.ps1` — Post-migration script (network restore, IPv6 disable, disk validation).
- Added `README_PrePostMigration.md` — Documentation for the two new scripts.

### What Was Removed
- Removed `Hidden_Devices_Remove.ps1` (v1.3) — Superseded by `Hidden_Devices_Remove_Total_v3_0.ps1`.
- Removed `PostCutover_Network_Sanity.ps1` (v2.2) — Superseded by `Hidden_Devices_Remove_Total_v3_0.ps1`.
- Removed `README_Hidden_Devices_Remove.md` and `README_PostCutover_Network_Sanity.md` — No longer needed.

### Current Scripts

| Script | Purpose |
|--------|---------|
| `Windows_PreMigration_Fase1_v3.5.ps1` | Run BEFORE migration |
| `Windows_PostMigration_Fase2_v3.5.ps1` | Run AFTER migration |
| `Hidden_Devices_Remove_Total_v3_0.ps1` | Cleanup ghost VMware devices (full toolkit with `-Aggressive` mode) |
| `Force_VMwareToolsRemove.ps1` | Last resort forceful VMware Tools removal |
