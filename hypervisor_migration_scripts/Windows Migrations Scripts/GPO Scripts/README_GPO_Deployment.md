# GPO Deployment — Pre-Migration Script

Guide for deploying `Windows_PreMigration_Fase1_v1.0_GPO.ps1` via Group Policy to an Active Directory Organizational Unit (OU).

This is the **unattended version** of the pre-migration script. It runs silently with no user prompts, controlled entirely via parameters. All output is written to a per-VM log file.

---

## Differences from the Interactive Version

| Feature | Interactive (v3.5) | GPO Edition (v1.0_GPO) |
|---------|-------------------|----------------------|
| Password input | User types it on screen | Passed via `-Password` parameter |
| VMware Tools removal | Asks yes/no | Controlled by `-RemoveVMwareTools` switch |
| Console output | Color-coded on screen | Written to log file per VM |
| Shutdown | Commented out | Controlled by `-ShutdownAfter` switch |
| User interaction | Required | None — fully unattended |

---

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-Password` | **Yes** | — | Password for the migration user account |
| `-RemoveVMwareTools` | No | Off | Silently uninstall VMware Tools |
| `-ShutdownAfter` | No | Off | Shut down the VM after script completes |
| `-MigrationUser` | No | `migrationadmin` | Name of the local admin account to create |
| `-WorkingDir` | No | `C:\Migration` | Working directory for backup and log files |

---

## Step-by-Step GPO Deployment

### 1. Prepare the Script Share

Create a network share accessible by all target VMs (read-only for computer accounts):

```
\\YourFileServer\Migration\Windows_PreMigration_Fase1_v1.0_GPO.ps1
```

Set permissions:
- **Domain Computers** → Read & Execute
- **Domain Admins** → Full Control

### 2. Create the GPO

1. Open **Group Policy Management Console** (gpmc.msc)
2. Right-click your target **OU** → **Create a GPO in this domain, and Link it here...**
3. Name it: `Pre-Migration - Network Backup and User Creation`

### 3. Configure the Startup Script

1. Right-click the new GPO → **Edit**
2. Navigate to:
   ```
   Computer Configuration → Policies → Windows Settings → Scripts (Startup/Shutdown) → Startup
   ```
3. Click the **PowerShell Scripts** tab
4. Click **Add**
5. Set:
   - **Script Name:** `\\YourFileServer\Migration\Windows_PreMigration_Fase1_v1.0_GPO.ps1`
   - **Parameters:** `-Password "YourP@ss123" -RemoveVMwareTools`

### 4. (Optional) Configure PowerShell Execution Policy

If the target VMs have a restricted execution policy, add this to the same GPO:

```
Computer Configuration → Policies → Administrative Templates → 
  Windows Components → Windows PowerShell → Turn on Script Execution
  → Enabled → Allow local scripts and remote signed scripts
```

### 5. Apply to Target OU

1. In Group Policy Management, ensure the GPO is linked to the correct OU
2. (Optional) Use **Security Filtering** to target only specific VMs
3. (Optional) Use **WMI Filtering** to target only VMware VMs:
   ```
   SELECT * FROM Win32_ComputerSystem WHERE Manufacturer LIKE "%VMware%"
   ```

### 6. Force GPO Update (Optional)

To apply immediately without waiting for the next reboot:

```powershell
# Run on target VMs or via remote PowerShell
gpupdate /force
# Then reboot to trigger the startup script
Restart-Computer -Force
```

---

## What Happens on Each VM

When a VM in the target OU reboots:

1. GPO startup script runs **before user login**
2. Network config is backed up to `C:\Migration\network_backup.xml`
3. Migration user account is created (if it doesn't exist)
4. VMware Tools is uninstalled (if `-RemoveVMwareTools` was specified)
5. A log file is created: `C:\Migration\PreMigration_HOSTNAME_TIMESTAMP.log`

---

## Log Files

Each VM generates its own log file at:

```
C:\Migration\PreMigration_SERVERNAME_20260222_031500.log
```

Example log output:

```
2026-02-22 03:15:00 [INFO] ============================================================
2026-02-22 03:15:00 [INFO] Windows VM Pre-Migration Script (GPO Edition) v3.5
2026-02-22 03:15:00 [INFO] Computer: YOURSERVER01
2026-02-22 03:15:00 [INFO] ============================================================
2026-02-22 03:15:00 [INFO] --- Phase 1: Backing up network configuration ---
2026-02-22 03:15:00 [INFO] Modern PowerShell (v5) detected. Using Get-NetAdapter.
2026-02-22 03:15:01 [INFO] Processing adapter: 'Ethernet0'
2026-02-22 03:15:01 [SUCCESS] Network backup saved to 'C:\Migration\network_backup.xml'.
2026-02-22 03:15:01 [INFO] --- Phase 2: Creating local user 'migrationadmin' ---
2026-02-22 03:15:02 [SUCCESS] User 'migrationadmin' created and added to Administrators (Modern Method).
2026-02-22 03:15:02 [INFO] --- Phase 3: VMware Tools check ---
2026-02-22 03:15:30 [INFO] VMware Tools found: 'VMware Tools' (12.3.5). Uninstalling silently...
2026-02-22 03:16:15 [SUCCESS] VMware Tools uninstalled successfully (exit code: 0).
2026-02-22 03:16:15 [INFO] --- Phase 4: Completion ---
2026-02-22 03:16:15 [SUCCESS] Script complete. VM is ready for migration.
```

---

## Usage Examples

### GPO — Basic (backup network + create user only)

```
Script: \\FileServer\Migration\Windows_PreMigration_Fase1_v1.0_GPO.ps1
Parameters: -Password "MyP@ss123"
```

### GPO — Full (backup + user + remove VMware Tools)

```
Script: \\FileServer\Migration\Windows_PreMigration_Fase1_v1.0_GPO.ps1
Parameters: -Password "MyP@ss123" -RemoveVMwareTools
```

### GPO — Full with shutdown

```
Script: \\FileServer\Migration\Windows_PreMigration_Fase1_v1.0_GPO.ps1
Parameters: -Password "MyP@ss123" -RemoveVMwareTools -ShutdownAfter
```

### GPO — Custom user and directory

```
Script: \\FileServer\Migration\Windows_PreMigration_Fase1_v1.0_GPO.ps1
Parameters: -Password "MyP@ss123" -MigrationUser "svc_migrate" -WorkingDir "D:\MigrationData"
```

### Manual run on a single VM (for testing)

```powershell
.\Windows_PreMigration_Fase1_v1.0_GPO.ps1 -Password "MyP@ss123" -RemoveVMwareTools
```

---

## Security Considerations

- The **password is visible** in the GPO script parameters. Use a temporary migration password and change it after migration, or use a Group Managed Service Account (gMSA) approach.
- Consider using **Security Filtering** on the GPO to limit which VMs are affected.
- The **WMI Filter** (`WHERE Manufacturer LIKE "%VMware%"`) ensures only VMware VMs are targeted.
- **Remove the GPO** after migration is complete to prevent the script from running on future reboots.
- **Delete the migration user** on each VM after migration is finished.

---

## Verification

After deployment, check the target VMs:

```powershell
# Check if backup was created
Test-Path C:\Migration\network_backup.xml

# Check if user was created
Get-LocalUser migrationadmin

# Check logs
Get-Content C:\Migration\PreMigration_*.log

# Check if VMware Tools was removed
Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "VMware Tools" }
```

---

## License

MIT

## Maintainer

Luciano Patrão
