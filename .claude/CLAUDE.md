# DevBox — Azure VM pro vzdálený vývoj

## Co to je

Terraform konfigurace, která vytvoří Azure VM sloužící jako vzdálený Docker host pro devcontainery generované pomocí [claude-devcontainer-generator](https://github.com/keeema/claude-devcontainer-generator). Na VM běží víc devcontainerů současně, vývojář se připojuje přes VS Code Remote nebo JetBrains SSH Interpreter.

## Architektura

```
MacBook (VS Code / PyCharm / prohlížeč)
│
│ Tailscale VPN (žádná veřejná IP)
│
Azure VM "devbox" (B4as_v2, 4 vCPU, 16 GB RAM, Ubuntu 24.04)
├── Docker Engine
├── Tailscale
├── Portainer (web UI, port 9443)
│
├── projekt-a (docker-compose)
│   ├── devcontainer (SSH :2222, Claude v tmux)
│   ├── postgres
│   └── redis
│
├── projekt-b (docker-compose)
│   ├── devcontainer (SSH :2223, Claude v tmux)
│   └── mongo
│
├── projekt-c (docker-compose)
│   ├── devcontainer (SSH :2224, Claude v tmux)
│   └── postgres
│
├── Docker volumes
│   ├── claude-shared             (sdílené credentials)
│   ├── projekt-a-claude-project
│   ├── projekt-a-commandhistory
│   ├── projekt-b-claude-project
│   ├── ...
│   └── portainer_data
│
└── ~/projects/
    ├── projekt-a-devcontainer/
    ├── projekt-a/
    ├── projekt-b-devcontainer/
    ├── projekt-b/
    ├── projekt-c-devcontainer/
    └── projekt-c/
```

## Jak se vývojář připojuje

### VS Code (přes Docker socket — žádný extra port)

1. VS Code → `Cmd+Shift+P` → "Remote-SSH: Connect to Host" → `<vm_user>@<tailscale_ip>`
2. SSH session na VM (port 22), VS Code nainstaluje svůj server na VM
3. Otevře `~/projects/projekt-a-devcontainer`
4. "Reopen in Container" → VS Code přes `docker exec` spustí svůj server uvnitř kontejneru
5. Druhé VS Code okno → stejný postup, jiný projekt → běží současně

VS Code používá Docker socket (`/var/run/docker.sock`), ne TCP porty. Víc VS Code oken se připojuje na VM přes stejný SSH port 22 (víc současných SSH sessions je standardní chování).

### PyCharm / JetBrains (přes SSH port do kontejneru)

JetBrains IDE neumí Dev Containers. Místo toho používá SSH Remote Interpreter přímo do kontejneru:

- Host: `<tailscale_ip>`, Port: 2222 (nebo 2223, 2224...), User: `node`
- Každý kontejner má unikátní SSH port (nastavený při generování přes `--ssh-port`)

### Portainer (prohlížeč, i z mobilu)

- `https://<tailscale_ip>:9443`
- Start/stop kontejnerů, logy, resource monitoring
- Přístupný jen přes Tailscale VPN

### Terminál / mobil

- SSH na VM → `docker exec -it <kontejner> bash` → `tmux attach -t claude`
- Z mobilu přes Termius nebo Tailscale SSH

## Co Terraform vytvoří

### Azure resources

1. **Resource Group** — použije existující (vstupní proměnná)
2. **Virtual Network + Subnet** — izolovaná síť pro VM
3. **Network Security Group** — povolený jen Tailscale UDP 41641 inbound, vše ostatní deny
4. **Network Interface** — bez veřejné IP adresy
5. **Linux VM** (Standard_B4as_v2) — Ubuntu 24.04 LTS, burstable
6. **OS Disk** — 128 GB Standard SSD (Premium SSD volitelně)
7. **Auto-shutdown schedule** — deallocate VM ve 22:00 (šetří náklady)

### Cloud-init provisioning

Cloud-init se spustí při prvním startu VM a nainstaluje:

1. **Docker Engine** — apt repozitář, docker-ce, docker-compose-plugin
2. **Tailscale** — nainstaluje, spustí `tailscale up --auth-key=<key> --ssh`
3. **Portainer** — Docker kontejner na portu 9443
4. **Git** — pro klonování repozitářů
5. **Uživatel** — přidá do skupiny `docker`, nastaví SSH klíč
6. **Docker volume** — `docker volume create claude-shared`

### Tailscale SSH

Tailscale SSH umožňuje přístup bez správy SSH klíčů na VM. Po `tailscale up --ssh` se můžete připojit z jakéhokoliv zařízení ve vaší Tailscale síti bez konfigurace authorized_keys. VS Code Remote-SSH funguje s Tailscale SSH.

## Terraform proměnné

### Povinné

| Proměnná              | Typ                | Popis                                                                                                                          |
| --------------------- | ------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| `resource_group_name` | string             | Název existující Azure Resource Group                                                                                          |
| `tailscale_auth_key`  | string (sensitive) | Tailscale auth key pro připojení VM do sítě. Vytvořte na https://login.tailscale.com/admin/settings/keys — reusable, ephemeral |

### Volitelné

| Proměnná                 | Default                          | Popis                                                                |
| ------------------------ | -------------------------------- | -------------------------------------------------------------------- |
| `vm_name`                | `"devbox"`                       | Název VM v Azure i hostname v Tailscale                              |
| `location`               | `"westeurope"`                   | Azure region                                                         |
| `vm_size`                | `"Standard_B4as_v2"`             | Velikost VM (4 vCPU, 16 GB RAM)                                      |
| `os_disk_size_gb`        | `128`                            | Velikost OS disku v GB                                               |
| `os_disk_type`           | `"StandardSSD_LRS"`              | Typ disku (StandardSSD_LRS / Premium_LRS)                            |
| `admin_username`         | `"devuser"`                      | Uživatelské jméno na VM                                              |
| `ssh_public_key`         | `"~/.ssh/id_rsa.pub"`            | Cesta k veřejnému SSH klíči (fallback pokud Tailscale SSH nefunguje) |
| `auto_shutdown_time`     | `"2200"`                         | Čas auto-shutdown ve formátu HHMM (lokální čas)                      |
| `auto_shutdown_timezone` | `"Central Europe Standard Time"` | Časová zóna pro auto-shutdown                                        |

## Terraform outputs

| Output           | Popis                                       |
| ---------------- | ------------------------------------------- |
| `vm_id`          | Azure resource ID VM                        |
| `vm_private_ip`  | Privátní IP v Azure VNet (ne Tailscale IP)  |
| `tailscale_note` | Instrukce jak najít Tailscale IP            |
| `portainer_url`  | URL Portaineru (s Tailscale IP placeholder) |
| `ssh_command`    | Příkaz pro SSH připojení                    |

Tailscale IP není známá při `terraform apply` — VM ji dostane až po startu. Output obsahuje instrukce: `tailscale status` nebo zkontrolujte Tailscale admin konzoli.

## Struktura projektu

```
devbox-infra/
  ├── main.tf                 ← provider, data source pro resource group
  ├── variables.tf            ← vstupní proměnné
  ├── outputs.tf              ← výstupní hodnoty
  ├── vm.tf                   ← VM, NIC, NSG, VNet
  ├── cloud-init.tpl          ← cloud-init šablona (Docker, Tailscale, Portainer)
  ├── terraform.tfvars.example ← příklad konfigurace
  ├── .gitignore              ← terraform.tfvars, .terraform/, *.tfstate
  ├── CLAUDE.md               ← tento soubor
  └── README.md
```

## Použití

```bash
# 1. Nakonfigurujte proměnné
cp terraform.tfvars.example terraform.tfvars
# Upravte terraform.tfvars — resource_group_name, tailscale_auth_key

# 2. Přihlaste se do Azure
az login

# 3. Inicializujte Terraform
terraform init

# 4. Zkontrolujte plán
terraform plan

# 5. Vytvořte VM
terraform apply

# 6. Počkejte ~3 minuty na cloud-init, pak:
#    - Najděte Tailscale IP v admin konzoli (https://login.tailscale.com/admin/machines)
#    - Otevřete Portainer: https://<tailscale_ip>:9443
#    - VS Code: Remote-SSH → <admin_username>@<tailscale_ip>
```

## Denní workflow

```bash
# Ráno — nastartujte VM (pokud byla auto-shutdown)
az vm start -g <resource_group> -n devbox

# VM naběhne, Tailscale se automaticky připojí, Portainer a kontejnery běží
# → VS Code → Remote-SSH → otevřete devcontainer repo → Reopen in Container

# Večer — VM se vypne automaticky ve 22:00 (auto-shutdown)
# Nebo ručně:
az vm deallocate -g <resource_group> -n devbox
```

**Důležité:** `deallocate` (ne `stop`) uvolní compute hardware a přestanete platit za CPU. Disk zůstává a platíte jen za něj (~€8/měsíc za 128 GB Standard SSD). Data na disku (Docker images, volumes, projekty) přežijí deallocate.

## Cenová kalkulace

| Položka                      | Cena           |
| ---------------------------- | -------------- |
| B4as_v2 compute (242h/měsíc) | ~€37/měsíc     |
| 128 GB Standard SSD (24/7)   | ~€8/měsíc      |
| **Celkem**                   | **~€45/měsíc** |

Předpoklad: pracovní dny 7:00–18:00 (~242h/měsíc). Auto-shutdown ve 22:00 jako pojistka.

## Konvence kódu

- Terraform ≥ 1.5
- AzureRM provider ≥ 3.0
- Soubory rozdělené podle účelu (vm.tf, variables.tf, outputs.tf)
- Žádné moduly — flat struktura, jednoduchost
- Cloud-init jako template file (`.tpl`), ne inline
- Sensitive proměnné označené `sensitive = true`
- Žádné hardcoded hodnoty — vše přes proměnné s rozumnými defaulty

## Bezpečnost

- Žádná veřejná IP — přístup výhradně přes Tailscale VPN
- NSG povoluje jen Tailscale UDP port 41641 (pro přímé P2P spojení, snižuje latenci)
- SSH klíč jako fallback autentizace, primárně Tailscale SSH
- Tailscale auth key je sensitive — nikdy v gitu, jen v `.tfvars` (gitignored)
- Portainer přístupný jen z Tailscale sítě
- VM uživatel je v `docker` skupině, ne root

## TODO

- [ ] main.tf — provider azurerm, data source pro resource group
- [ ] variables.tf — všechny proměnné s popisy a defaulty
- [ ] vm.tf — VNet, Subnet, NSG, NIC, VM, auto-shutdown
- [ ] cloud-init.tpl — Docker, Tailscale, Portainer, claude-shared volume
- [ ] outputs.tf — VM ID, IP, instrukce
- [ ] terraform.tfvars.example
- [ ] .gitignore
- [ ] README.md
