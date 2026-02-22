# GPO Scripts

Unattended versions of the migration scripts for deployment via Active Directory Group Policy to an Organizational Unit (OU).

These scripts run silently with no user prompts — all options are controlled via parameters.

## Scripts

| Script | Purpose | Version |
|--------|---------|---------|
| `Windows_PreMigration_Fase1_v1.0_GPO.ps1` | Pre-migration: network backup, user creation, VMware Tools removal (unattended) | v1.0 |

## Documentation

See `README_GPO_Deployment.md` for the full step-by-step guide on how to configure the GPO, set up the file share, apply WMI filters, and verify the deployment.
