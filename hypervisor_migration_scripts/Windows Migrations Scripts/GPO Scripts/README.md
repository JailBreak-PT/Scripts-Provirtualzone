# GPO Scripts

Unattended versions of the migration scripts for deployment via Active Directory Group Policy to an Organizational Unit (OU).

These scripts run silently with no user prompts — all options are controlled via parameters.

## Scripts

| Script | Purpose | Version |
|--------|---------|---------|
| `Windows_PreMigration_Fase1_v1.0_GPO.ps1` | Pre-migration: network backup, user creation, VMware Tools removal (unattended) | v1.0 |

## Documentation

See `README_GPO_Deployment.md` for the full step-by-step guide on how to configure the GPO, set up the file share, apply WMI filters, and verify the deployment.

## Disclaimer
USE AT YOUR OWN RISK. These scripts are provided "as is" without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement. In no event shall the author be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the scripts or the use or other dealings in the scripts.

Always test in a non-production environment before running on any production or critical infrastructure. The author assumes no responsibility for data loss, system downtime, misconfigurations, or any other issues that may arise from the use of these scripts. Every environment is different — it is the user's responsibility to review, understand, and validate the scripts before execution.
By using these scripts, you accept full responsibility for any outcomes.
