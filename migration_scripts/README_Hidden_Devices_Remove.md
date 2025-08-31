# Hidden\_Devices\_Remove.ps1

A focused PowerShell script to safely find and remove old, non-present ('ghost') VMware hardware devices from a Windows VM after it has been migrated to a new platform like Hyper-V or Proxmox.

  - **Simple and Fast:** Designed for a quick and easy device cleanup.
  - **Safe by Design:** Includes multiple safety checks and refuses to run if VMware Tools is detected.
  - **Interactive Confirmation:** Shows you exactly what will be removed and waits for your approval.
  - **Effective Search:** Uses a proven list of patterns to find all relevant VMware hardware.
  - **Clean Output:** Provides a clear, step-by-step report of its progress.

-----

## Why Use This Script?

After migrating a virtual machine, leftover VMware devices remain in the system registry. These hidden devices can cause driver conflicts, system instability, or simply create clutter in Device Manager. This script provides a safe, interactive, and effective way to clean the system.

It is designed to be run **before** reconfiguring networking to prevent potential connectivity issues.

-----

## Comparison to `PostCutover_Network_Sanity.ps1`

This script (`Hidden_Devices_Remove.ps1`) is designed for one specific job: to be a **simple and fast** way to remove non-present hardware. It is ideal for situations where you just need a quick device cleanup without extra features.

The `PostCutover_Network_Sanity.ps1` script is a **more comprehensive, all-in-one tool**. It performs a much deeper cleaning process, which includes:

  - Automated backups before any changes.
  - A function to restore drivers and IP settings.
  - Cleanup of the Windows DriverStore.
  - Additional network tasks like flushing DNS and resetting Winsock.

**Choose this script (`Hidden_Devices_Remove.ps1`) for speed and simplicity. Choose `PostCutover_Network_Sanity.ps1` for a complete, reversible, and fully automated hygiene process.**

-----

## Key Features

  - **Safe by Design:** Includes multiple safety checks. It warns you if run on a VMware platform and refuses to run if VMware Tools is still installed.
  - **Effective Search:** Uses a proven list of device name patterns (including `*VMware*`, `vmxnet3*`, and the emulated Intel E1000 NIC) to find all relevant hardware.
  - **Interactive Confirmation:** Shows you a clear, formatted list of all devices it will remove and waits for your confirmation before making any changes.
  - **Clean Output:** Provides a simple, step-by-step report of its progress, making the process easy to follow.
  - **Universal Compatibility:** Uses the built-in `pnputil.exe` utility, ensuring it works on all modern Windows versions without needing extra modules.

-----

## Requirements

  - Windows PowerShell 5.1 or later.
  - Must be run with Administrator privileges.

-----

## How to Use

1.  **Important:** For best results, uninstall VMware Tools **before** migrating the VM.
2.  Copy the `Hidden_Devices_Remove v1.3.ps1` script to the newly migrated VM.
3.  Open PowerShell **as an Administrator**.
4.  Navigate to the script's location and run it:
    ```powershell
    .\'Hidden_Devices_Remove v1.3.ps1'
    ```
5.  The script will show you a summary of the devices it found. Carefully review this list.
6.  Press **Enter** to confirm and begin the removal process.
7.  **Reboot the VM** after the script completes to finalize the changes.

-----

## The Process (What it Does)

The script follows a safe, three-step process:

1.  **[PASSO 1/3] Find Devices:**

      - It verifies that it's running as an Administrator on a non-VMware hypervisor.
      - It confirms that VMware Tools is not installed.
      - It searches the system for all hardware devices (including hidden ones) that match its list of VMware-related name patterns.

2.  **[PASSO 2/3] Confirm and Remove:**

      - It displays a clean, formatted table of all the non-present devices it found.
      - It pauses and waits for you to press Enter to proceed.
      - It then iterates through the list, using `pnputil.exe` to silently remove each device and reports the success of each operation.

3.  **[PASSO 3/3] Rescan Hardware:**

      - After all devices are removed, it runs a final hardware scan (`pnputil /scan-devices`) to allow Windows to cleanly detect the new (e.g., Hyper-V) devices.

-----

## License

MIT

-----

## Maintainer

Luciano Patrao