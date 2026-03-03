# DevBox — Azure VM for Remote Development

Terraform configuration that provisions an Azure VM as a remote Docker host for devcontainers. The VM runs multiple devcontainers simultaneously, accessed exclusively via Tailscale VPN (no public IP).

## Architecture

```
MacBook (VS Code / PyCharm / browser)
│
│ Tailscale VPN (no public IP)
│
Azure VM "devbox" (B4as_v2, 4 vCPU, 16 GB RAM, Ubuntu 24.04)
├── Docker Engine
├── Tailscale
├── Portainer (web UI, port 9443)
├── devcontainer per project (SSH ports 2222+)
├── Docker volumes (claude-shared, per-project)
└── ~/projects/
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az login`)
- An existing Azure Resource Group
- A [Tailscale auth key](https://login.tailscale.com/admin/settings/keys) (reusable, ephemeral recommended)
- SSH public key at `~/.ssh/id_rsa.pub` (or specify path via variable)

## Quick Start

```bash
# 1. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set resource_group_name

# 2. Store Tailscale auth key in macOS Keychain
security add-generic-password -a "$USER" -s "tailscale-auth-key" -w "<your-tskey-auth-...>"

# 3. Export the key before running Terraform
export TF_VAR_tailscale_auth_key=$(security find-generic-password -a "$USER" -s "tailscale-auth-key" -w)

# 4. Log in to Azure
az login

# 5. Initialize and deploy
terraform init
terraform plan
terraform apply

# 6. Wait ~3 minutes for cloud-init, then:
#    - Find Tailscale IP at https://login.tailscale.com/admin/machines
#    - Open Portainer: https://<tailscale_ip>:9443
#    - VS Code: Remote-SSH → devuser@devbox
```

## Daily Workflow

```bash
# Morning — start the VM (if auto-shutdown stopped it)
az vm start -g <resource_group> -n devbox

# VM boots, Tailscale reconnects automatically, containers resume
# → VS Code → Remote-SSH → open devcontainer repo → Reopen in Container

# Evening — VM auto-shuts down at 22:00, or manually:
az vm deallocate -g <resource_group> -n devbox
```

**Note:** Use `deallocate` (not `stop`) to release compute and stop billing for CPU. Disk data (Docker images, volumes, projects) survives deallocate.

## Variables

| Variable | Default | Description |
|---|---|---|
| `resource_group_name` | *(required)* | Name of an existing Azure Resource Group |
| `tailscale_auth_key` | *(required)* | Tailscale auth key (sensitive) |
| `vm_name` | `"devbox"` | VM name in Azure and Tailscale hostname |
| `location` | `"westeurope"` | Azure region |
| `vm_size` | `"Standard_B4as_v2"` | VM size (4 vCPU, 16 GB RAM) |
| `os_disk_size_gb` | `128` | OS disk size in GB |
| `os_disk_type` | `"Standard_LRS"` | Disk type (Standard_LRS / Premium_LRS) |
| `admin_username` | `"devuser"` | VM admin username |
| `ssh_public_key` | `"~/.ssh/id_rsa.pub"` | Path to SSH public key |
| `auto_shutdown_time` | `"2200"` | Auto-shutdown time (HHMM) |
| `auto_shutdown_timezone` | `"Central Europe Standard Time"` | Timezone for auto-shutdown |

## Outputs

| Output | Description |
|---|---|
| `vm_id` | Azure resource ID of the VM |
| `vm_private_ip` | Private IP in Azure VNet (not the Tailscale IP) |
| `tailscale_note` | Instructions to find the Tailscale IP |
| `portainer_url` | Portainer web UI URL |
| `ssh_command` | SSH command using Tailscale hostname |

## Cost Estimate

| Item | Cost |
|---|---|
| B4as_v2 compute (~242h/month) | ~€37/month |
| 128 GB Standard SSD (24/7) | ~€8/month |
| **Total** | **~€45/month** |

Assumes weekday usage 7:00–18:00 (~242h/month). Auto-shutdown at 22:00 as safety net.

## Cleanup

```bash
terraform destroy
```

This removes all Azure resources created by this configuration (VM, disk, NIC, NSG, VNet).
