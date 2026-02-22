# Linux VMware to Hyper-V Migration Scripts

A comprehensive suite of PowerShell and Bash scripts to automate and standardize the migration of Linux virtual machines from VMware to Hyper-V. This toolchain is designed to be robust, idempotent, and compatible with a wide range of new and legacy Linux distributions (RHEL, CentOS, Oracle Linux, Debian, Ubuntu, etc.).

- **Automated Workflow:** Uses PowerShell to remotely prepare and execute migration tasks.
- **Multi-Distro Support:** Contains specific logic to handle RPM/DEB packages, systemd/SysVinit services, and GRUB Legacy/GRUB2 bootloaders.
- **Safe by Design:** Includes pre-migration backups, post-migration validation, and a clear rollback procedure.
- **Idempotent:** Scripts can be run multiple times without causing harm, intelligently skipping steps that are already complete.
- **Offline Capable:** Designed to work without internet access on the target VMs, using locally staged driver packages or ISOs.

-----

## Why Use This Toolchain?

Migrating a Linux VM between hypervisors can be a complex process. This toolchain automates the most critical and error-prone steps:

- **Network Configuration:** Automatically backs up the original static IP settings and restores them after the migration, preventing loss of connectivity.
- **Driver Management:** Ensures the correct Hyper-V drivers are present in the boot configuration, preventing a "no boot" scenario.
- **System Cleanup:** Properly removes old VMware Tools to avoid driver conflicts and system instability.
- **Bootloader Handling:** Safely creates a temporary boot entry for the first boot on Hyper-V and provides a mechanism to make it permanent after a successful validation.

-----

## The Scripts

This repository contains a full workflow of coordinated scripts.

| Script Name                                  | Purpose                                                                                                 |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `1_Linux_SSH_Bootstrap.ps1`                  | **(PowerShell)** Establishes initial key-based SSH trust with a Linux VM. Runs once per VM.                |
| `2_Linux_Run_Copy.ps1`                       | **(PowerShell)** Copies all necessary Bash scripts to the target VM and executes the pre-migration process. |
| `Linux_Pre_Migracao_AllDistros.sh`           | **(Bash)** The main preparation script. Backs up the network, removes VMware Tools, and prepares GRUB.      |
| `Linux_Post_Migration.sh`                    | **(Bash)** The first script to run after booting on Hyper-V. Restores the network and makes the boot permanent. |
| `Post_Migration_Validation.sh`               | **(Bash)** A comprehensive validation tool that checks system health and offers to finalize the migration.    |
| `Linux_rollback_validacao_migration.sh`      | **(Bash)** A utility to revert a VM to its original VMware state if the migration fails.                |

-----

## Requirements

- **Windows Host:** PowerShell 5.1 or later, with Administrator privileges.
- **Linux VM:** Root access.
- **Script Files:** The complete collection of scripts from this repository.

-----

## How to Use (The Migration Workflow)

The process is divided into pre-migration, migration, and post-migration phases.

### Phase 1: Pre-Migration (on VMware)

This phase prepares the Linux VM for the move.

1.  **Install SSH Key:**
    -   Edit `1_Linux_SSH_Bootstrap.ps1` to set the target `$IP`.
    -   Run the script. You will be prompted for the `root` password once.
        ```powershell
        .\1_Linux_SSH_Bootstrap.ps1
        ```

2.  **Execute Pre-Migration:**
    -   Edit `2_Linux_Run_Copy.ps1` to set the target `$IP`.
    -   Run the script. It will copy all files and run the main preparation script on the remote VM.
        ```powershell
        .\2_Linux_Run_Copy.ps1
        ```
    -   Once this script completes successfully, shut down the VM in VMware.

### Phase 2: Migration

- At this point, the VM is fully prepared. Use your preferred tool (SCVMM, Veeam, etc.) to migrate the VM's virtual disks from the VMware datastore to your Hyper-V host and create a new VM using them.

### Phase 3: Post-Migration (on Hyper-V)

1.  **First Boot (Critical Step):**
    -   Power on the VM in Hyper-V and open the console.
    -   At the GRUB boot menu, you **must manually select** the entry named **`Hyper-V (pré-migração)...`**. This ensures the VM boots with the necessary drivers.

2.  **Restore Network & Finalize Boot:**
    -   After the VM boots, connect to it via SSH.
    -   Run the post-migration script. This will restore the original static IP address and make the Hyper-V boot entry the permanent default.
        ```bash
        cd /root/migracao_files
        bash ./Linux_Post_Migration.sh
        ```

3.  **Validate and Clean Up:**
    -   Run the final validation script to ensure everything is working correctly.
        ```bash
        bash ./Post_Migration_Validation.sh
        ```
    -   If all critical checks pass, the script will ask if you want to remove the temporary "pré-migração" GRUB entry. Press `s` to confirm and complete the process.

-----

## Disclaimer
USE AT YOUR OWN RISK. These scripts are provided "as is" without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement. In no event shall the author be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the scripts or the use or other dealings in the scripts.

Always test in a non-production environment before running on any production or critical infrastructure. The author assumes no responsibility for data loss, system downtime, misconfigurations, or any other issues that may arise from the use of these scripts. Every environment is different — it is the user's responsibility to review, understand, and validate the scripts before execution.
By using these scripts, you accept full responsibility for any outcomes.

## License

MIT

-----

## Maintainer

Luciano Patrao
