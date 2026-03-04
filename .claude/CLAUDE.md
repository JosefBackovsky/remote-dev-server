# remote-dev-server

## Co to je

Setup skripty pro remote development host. Podporuje dva targety:
- **Azure VM** — Terraform provisioning s cloud-init
- **Debian server** — přímá instalace přes shell skript

Na hostu pak běží devcontainery generované pomocí [claude-devcontainer-generator](https://github.com/JosefBackovsky/claude-devcontainer-generator).

## Architektura

```
scripts/           sdílené skripty (Docker, Tailscale, Portainer, volumes)
  ↑                   ↑
  │                   │
azure/             debian/
cloud-init.tpl     install.sh
(embedduje         (volá skripty
 skripty přes       přímo z disku)
 write_files)
```

Každý skript v `scripts/` je:
- **Idempotentní** — bezpečný pro opakované spuštění
- **Distro-agnostický** — detekuje Ubuntu/Debian přes `/etc/os-release`
- **Parametrizovaný** — konfigurace přes argumenty příkazové řádky

## Sdílené skripty

| Skript | Guard | Chování |
|--------|-------|---------|
| `docker.sh <user>` | `command -v docker` | Instalace Docker CE, daemon.json (před startem), user do docker group |
| `tailscale.sh <key> [hostname]` | `tailscale status` | Instalace + `tailscale up --ssh` |
| `portainer.sh` | `docker ps -a` | Nový kontejner, nebo `docker start` pokud stopped |
| `shared-volumes.sh <user>` | Přirozeně idempotentní | `docker volume create claude-shared`, `mkdir -p ~/projects` |

## Azure target

Terraform soubory v `azure/`. `cloud-init.tpl` embeduje skripty přes `write_files` (Terraform `file()` + `indent()`).

Důležité:
- `vm.tf` má `lifecycle { ignore_changes = [custom_data] }` — změna skriptů nevynutí re-create VM
- Terraform `file()` čte skripty z `../scripts/` relativně k `azure/`

## Debian target

`debian/install.sh` orchestruje volání skriptů:
1. Kontrola: ne-root + sudo přístup
2. Prerequisity: `curl`, `ca-certificates`, `gnupg`, `git`
3. Docker (přeskočí pokud existuje)
4. Tailscale (volitelný, `--tailscale KEY`)
5. Portainer
6. Shared volumes

Konfigurace přes CLI flags (`--username`, `--tailscale`, `--tailscale-hostname`).

## Konvence

- Bash skripty: `set -euo pipefail`, `shellcheck` clean
- Terraform: >= 1.5, AzureRM >= 3.0, flat struktura v `azure/`
- Sensitive data: nikdy v gitu (terraform.tfvars, .env jsou v .gitignore)
- Commit messages: conventional commits (feat/fix/docs)
