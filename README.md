# Scripts-Provirtualzone

Migration toolkit for virtual machines from VMware to Hyper-V (or Proxmox). Covers both Windows and Linux guest operating systems.

Designed for restricted enterprise environments — no internet access required, no external dependencies.

---

## Folders

| Folder | Description | Status |
|--------|-------------|--------|
| `Windows migrations script/` | Full toolkit for Windows VMs: pre-migration, post-migration, device cleanup, GPO automation | ✅ Active |
| `Linux migrations script/` | Toolchain for Linux VMs: pre-migration, post-migration, multi-distro support, PowerShell front-end | 🟡 On hold |

See each folder's README for full documentation, workflow guides, and script details.

---

## Latest Updates

### 22/02/2026 — Windows
* Added pre-migration script v3.5 (network backup, user creation, VMware Tools removal).
* Added post-migration script v3.5 (network restore, IPv6 disable, disk validation).
* Added GPO edition v1.0 for unattended AD OU deployment.
* Removed old superseded scripts — replaced by `Hidden_Devices_Remove_Total_v3_0.ps1`.

### 19/09/2025 — Windows
* Released unified cleanup toolkit v3.0 with `-Aggressive` mode.

### 07/09/2025 — Linux
* Added full Linux migration toolchain (RHEL, CentOS, Oracle Linux, Debian — EL6 to EL9).

### 05/09/2025
* Created separate folders for Windows and Linux migration scripts.

### 31/08/2025 — Windows
* Added PostCutover Network Sanity script for post-migration device cleanup.

---

## License

MIT

## Author

**Luciano Patrão**

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.
Luciano Patrão
