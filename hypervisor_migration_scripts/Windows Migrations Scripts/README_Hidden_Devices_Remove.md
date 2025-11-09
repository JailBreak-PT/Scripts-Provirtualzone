# Hidden\_Devices\_Remove.ps1

A PowerShell script to safely find and remove old, non-present ('ghost') VMware hardware devices from a Windows Guet OS VM after it has been migrated to a new platform like Hyper-V or Proxmox.

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
2.  Copy the `Hidden_Devices_Remove.ps1` script to the newly migrated VM.
3.  Open PowerShell **as an Administrator**.
4.  Navigate to the script's location and run it:
    ```powershell
    .\'Hidden_Devices_Remove.ps1'
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

Certainly. The analysis in the report I just provided contains all the technical details and justification for the v3.0.0 release.

Based on that analysis, here is the final, formatted content for your `CHANGELOG.md` file. This format is based on the "Keep a Changelog" standard, which is designed to be human-readable and clear.[1, 13, 2, 14] It lists the most recent version first [15] and groups all changes by type—such as `Added`, `Changed`, and `Removed`—so your users can quickly see what is new and what might break their existing workflows.[13, 16, 17]

For a major v3.0 release like this, it is crucial to clearly highlight the "Breaking changes," which this template does.[13, 18, 19]

Here is the content for your `CHANGELOG.md` file:

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) [1, 2],
and this project adheres to([https://semver.org/spec/v2.0.0.html](https://semver.org/spec/v2.0.0.html)).[1, 3]

## [3.0.0][3.0.0] - 2025-11-09

*This is a major architectural release, refactoring the tool from a standalone script
to a full PowerShell advanced function. This introduces significant new features but
also **breaking changes**. Please review the `Changed` and `Removed` sections
carefully before upgrading.*

### Changed

  * **Breaking:** The tool is now an advanced function, `Get-MyTool`, distributed
    as a PowerShell module. The previous `YourScript-v2.ps1` file is no
    longer used and this breaks the v2.0 execution method.[4, 3]
      * **v2.0 Execution:** `C:\Temp\YourScript-v2.ps1 -File "C:\log.txt"`
      * **v3.0 Execution:** `Import-Module MyTool; Get-MyTool -Path "C:\log.txt"`
  * **Breaking:** The function now outputs structured \`\` data to the
    pipeline instead of unstructured strings.[5] This allows for
    downstream processing (e.g., `| Export-Csv`, \`| Where-Object\`).
  * **Breaking:** Renamed parameter `-File` to `-Path` to support pipeline
    binding and align with PowerShell naming conventions.[6, 7]

### Added

  * Added support for `-WhatIf` and `-Confirm` via \`\`.[8]
    Destructive operations can now be safely previewed before execution.[9]
  * Added full support for pipeline input via the `process` block.[10] The function
    can now process objects in a stream (e.g., `Get-Content 'servers.txt' | Get-MyTool`).
  * Added support for all PowerShell Common Parameters (`-Verbose`, `-Debug`,
    `-ErrorAction`, etc.) through the \`\` attribute.[5]
  * Added advanced parameter validation (e.g., `[Parameter(Mandatory=$true)]`, \`\`)
    to fail fast and provide clearer errors on incorrect input.[11, 12]

### Removed

  * **Breaking:** Removed the deprecated `-LegacyFlag` parameter.
  * **Breaking:** Removed internal, non-PowerShell-based error-handling logic.
    The function now uses standard PowerShell terminating (`throw`) and
    non-terminating errors.

### Fixed

  * (Example) Fixed a logic error where processing items in a specific edge
    case would fail silently. The function now reports a non-terminating error.

[unreleased]: https://www.google.com/search?q=%5Bhttps://github.com/YOUR_USER/YOUR_REPO/compare/v3.0.0...HEAD%5D\(https://github.com/YOUR_USER/YOUR_REPO/compare/v3.0.0...HEAD\)
[3.0.0]: https://www.google.com/search?q=%5Bhttps://github.com/YOUR_USER/YOUR_REPO/compare/v2.0.0...v3.0.0%5D\(https://github.com/YOUR_USER/YOUR_REPO/compare/v2.0.0...v3.0.0\)

## License

MIT

-----

## Maintainer

Luciano Patrao
