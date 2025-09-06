# Scripts-Provirtualzone

07/09/2025

Added a complete and robust toolchain for the automated migration of Linux VMs from VMware to Hyper-V. This new suite, located in the "Linux migrations script" folder, provides a full end-to-end workflow.

Key features include:
- Pre-migration preparation (network backup, VMware Tools removal, safe GRUB modification).
- Post-migration validation with an interactive cleanup option.
- Universal compatibility across major distributions (RHEL, CentOS, Oracle Linux, Debian) and versions (e.g., EL6 to EL9).
- A PowerShell front-end for automating key deployment and remote execution.

31/08/2028

Added new script PostCutover_Network_Sanity.ps1 with some changes in
 case the VM still has the VMware tools installed in the VM. It will 
request to remove the VMware tools and then reboot

05/09/2025

Added two folders in the Migration script section. One for the Windows migrations script and one for the Linux migrations script
```


