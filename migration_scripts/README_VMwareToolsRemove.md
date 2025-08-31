# Force-RemoveVMwareTools.ps1

A "scorched-earth" PowerShell script to forcefully remove a broken or corrupted VMware Tools installation from a Windows system.

  - **Last Resort Tool:** Designed for when standard uninstall methods fail.
  - **Aggressive Cleaning:** Deletes services, files, drivers, and registry keys.
  - **Interactive Safety:** Requires explicit confirmation before starting.
  - **No Dependencies:** Uses only built-in Windows command-line tools.

-----

## ⚠️ IMPORTANT WARNING ⚠️

This script performs an aggressive, forceful removal. It does **not** run the official uninstaller.

It is designed as a **last resort** for situations where VMware Tools is corrupted and cannot be removed through "Add or Remove Programs" or the Microsoft Troubleshooter.

Running this on a healthy system is not recommended. A **system reboot is mandatory** after the script completes.

-----

## When to Use This Script

You should use this script when:

  - The standard VMware Tools uninstaller fails with an error (like `1603`).
  - VMware Tools does not appear in "Add or Remove Programs," but its services and files are still on the system.
  - The official Microsoft Program Install and Uninstall Troubleshooter is unable to remove the software.

-----

## Requirements

  - Windows PowerShell 5.1 or later.
  - Must be run with **Administrator** privileges.

-----

## How to Use

1.  Copy the `Force-RemoveVMwareTools.ps1` script to the target machine.
2.  Open PowerShell **as an Administrator**.
3.  Navigate to the script's location and run it:
    ```powershell
    .\Force-RemoveVMwareTools.ps1
    ```
4.  Read the warning carefully.
5.  Type **`YES`** and press **Enter** to confirm and begin the removal.
6.  **Reboot the machine immediately** after the script finishes.

-----

## The Process (What it Does)

The script performs a comprehensive, multi-step removal of all VMware Tools components:

1.  **Confirmation:** First, it requires you to type `YES` to ensure you want to proceed with the forceful removal.
2.  **Stop and Delete Services:** Stops and forcefully deletes common VMware Tools services (`VMTools`, `VGAuthService`, etc.).
3.  **Terminate Processes:** Terminates any lingering VMware Tools processes (`vmtoolsd.exe`, etc.) that may still be running.
4.  **Purge Drivers:** Finds all driver packages in the Windows DriverStore published by "VMware" and forcefully removes them using `pnputil.exe`.
5.  **Delete Files and Folders:** Deletes the VMware Tools installation directories from `Program Files` and `ProgramData`.
6.  **Scrub Registry:** Removes the main VMware Tools registry keys and its entry from the list of installed programs.

-----

## License

MIT

-----

## Maintainer

Luciano Patrao