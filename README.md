# flagship-landing-zone

Workload spokes for the Flagship Azure Landing Zone — prod and dev environments hosting the procurement demo app.

## What's here

- `landing-zone/` — Terraform for the prod and dev spokes
  - Spoke VNets peered to the hub from [flagship-platform](https://github.com/orealvic/flagship-platform)
  - App Service Plans + Web and API apps per environment
  - MySQL Flexible Server per environment (VNet-integrated, private DNS)
  - Key Vault per environment with private endpoint
  - Auto-shutdown Automation account that stops dev resources nights and weekends
- `.github/workflows/landing-zone-iac.yml` — caller workflow consuming the reusable workflow from [flagship-actions](https://github.com/orealvic/flagship-actions)

## Architecture

Hub-and-spoke topology:

```
Hub (10.10.0.0/16) ←── peered ──→ Prod spoke (10.20.0.0/16)
                  ←── peered ──→ Dev spoke  (10.30.0.0/16)
```

Each spoke has three subnets:
- `snet-app-service` — delegated to Microsoft.Web for VNet integration
- `snet-mysql` — delegated to Microsoft.DBforMySQL/flexibleServers
- `snet-private-endpoints` — for KV and any future PE-enabled services

## Dependencies

This stack reads outputs from `flagship-platform` via `terraform_remote_state`:
- Hub VNet ID and name (for spoke peering)
- Private DNS zone IDs (for PE registration)
- Network and shared resource group names

If you change the platform stack, this stack picks up the changes automatically on the next plan.

## Cost

Approximately **$1.60/day** when both environments are running. Dev auto-shutdown reduces this to ~**$1.10/day** average (dev compute and DB stopped roughly 16h/day weekdays, 48h on weekends).

## See also

- [flagship-docs](https://github.com/orealvic/flagship-docs) — architecture and ADRs
