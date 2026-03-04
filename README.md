# remote-dev-server

Setup scripts for remote development host — Docker, Portainer, shared volumes, and optionally Tailscale. Supports both Azure VM (Terraform) and Debian home server.

## Architecture

```
MacBook (VS Code / PyCharm / browser)
│
│ Tailscale VPN / LAN
│
Dev Host (Azure VM or Debian server)
├── Docker Engine
├── Tailscale (optional on Debian)
├── Portainer (web UI, port 9443)
├── devcontainer per project (SSH ports 2222+)
├── Docker volumes (claude-shared, per-project)
└── ~/projects/
```

## Quick Start: Debian Home Server

```bash
# 1. Copy to server
scp -r scripts/ debian/ user@server:~/remote-dev-server/

# 2. SSH and install
ssh user@server
cd ~/remote-dev-server
./debian/install.sh                    # defaults are fine for most setups
./debian/install.sh --tailscale KEY    # optionally install Tailscale
./debian/install.sh --help             # see all options

# 3. Re-login (for Docker group), then verify:
docker run --rm hello-world
```

**Note:** If a local firewall (`ufw`, `nftables`) is running, open port 9443 for Portainer access.

## Quick Start: Azure VM

```bash
cd azure

# 1. Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set resource_group_name

# 2. Set Tailscale auth key
export TF_VAR_tailscale_auth_key=$(security find-generic-password -a "$USER" -s "tailscale-auth-key" -w)

# 3. Deploy
az login
terraform init
terraform plan
terraform apply

# 4. Wait ~3 minutes for cloud-init, then:
#    - Find Tailscale IP: https://login.tailscale.com/admin/machines
#    - Portainer: https://<tailscale_ip>:9443
#    - SSH: ssh devuser@devbox
```

## Project Structure

```
remote-dev-server/
├── scripts/                    # Shared setup scripts
│   ├── docker.sh               # Install Docker Engine (Ubuntu + Debian)
│   ├── tailscale.sh            # Install and configure Tailscale
│   ├── portainer.sh            # Run Portainer container
│   └── shared-volumes.sh      # Create claude-shared volume + ~/projects
├── azure/                      # Azure VM target (Terraform)
│   ├── main.tf
│   ├── variables.tf
│   ├── vm.tf
│   ├── outputs.tf
│   ├── cloud-init.tpl
│   └── terraform.tfvars.example
├── debian/                     # Debian server target
│   └── install.sh
└── README.md
```

## Shared Scripts

All scripts in `scripts/` are idempotent (safe to run multiple times), distro-agnostic (Ubuntu/Debian), and parameterized via arguments.

| Script | Purpose | Parameters |
|--------|---------|------------|
| `docker.sh` | Install Docker Engine + compose plugin | `<username>` |
| `tailscale.sh` | Install Tailscale + `tailscale up` | `<auth_key> [hostname]` |
| `portainer.sh` | Run Portainer CE container | — |
| `shared-volumes.sh` | Create `claude-shared` volume + `~/projects` | `<username>` |

## Azure Variables

| Variable | Default | Description |
|---|---|---|
| `resource_group_name` | *(required)* | Name of an existing Azure Resource Group |
| `tailscale_auth_key` | *(required)* | Tailscale auth key (sensitive) |
| `vm_name` | `"devbox"` | VM name in Azure and Tailscale hostname |
| `location` | `"westeurope"` | Azure region |
| `vm_size` | `"Standard_B4as_v2"` | VM size (4 vCPU, 16 GB RAM) |
| `os_disk_size_gb` | `128` | OS disk size in GB |
| `os_disk_type` | `"StandardSSD_LRS"` | Disk type (StandardSSD_LRS / Premium_LRS) |
| `admin_username` | `"devuser"` | VM admin username |
| `ssh_public_key` | `"~/.ssh/id_ed25519_devbox.pub"` | Path to SSH public key |
| `auto_shutdown_time` | `"2200"` | Auto-shutdown time (HHMM) |
| `auto_shutdown_timezone` | `"Central Europe Standard Time"` | Timezone for auto-shutdown |

## Azure Outputs

| Output | Description |
|---|---|
| `vm_id` | Azure resource ID of the VM |
| `vm_private_ip` | Private IP in Azure VNet (not the Tailscale IP) |
| `tailscale_note` | Instructions to find the Tailscale IP |
| `portainer_url` | Portainer web UI URL |
| `ssh_command` | SSH command using Tailscale hostname |

## Changing OS Disk

Disk size and type can be changed via `os_disk_size_gb` and `os_disk_type` variables without recreating the VM. Terraform will automatically deallocate the VM, update the disk, and start it again (same as Azure Portal).

```bash
# Example: switch to Premium SSD
# In terraform.tfvars: os_disk_type = "Premium_LRS"
terraform apply
```

## Cost Estimate

| Item | Cost |
|---|---|
| B4as_v2 compute (~242h/month) | ~€37/month |
| 128 GB Standard SSD (24/7) | ~€8/month |
| **Total** | **~€45/month** |

Assumes weekday usage 7:00–18:00 (~242h/month). Auto-shutdown at 22:00 as safety net.

## Network Prerequisites

- Server must have internet access during installation
- If installation fails midway, re-run the install script — all scripts are idempotent
- For Debian: if `ufw` or `nftables` is active, ensure port 9443 is open for Portainer

## Cleanup

```bash
terraform destroy
```

This removes all Azure resources created by this configuration (VM, disk, NIC, NSG, VNet).
