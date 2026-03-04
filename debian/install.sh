#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install Docker, Portainer, and shared volumes on a Debian/Ubuntu server.

Options:
  --username USER         User for Docker group and ~/projects (default: current user)
  --tailscale KEY         Install Tailscale with the given auth key
  --tailscale-hostname H  Tailscale hostname (default: devbox)
  -h, --help              Show this help
EOF
  exit 0
}

# Defaults
USERNAME="$(whoami)"
TAILSCALE_AUTH_KEY=""
TAILSCALE_HOSTNAME="devbox"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --username)           USERNAME="$2"; shift 2 ;;
    --tailscale)          TAILSCALE_AUTH_KEY="$2"; shift 2 ;;
    --tailscale-hostname) TAILSCALE_HOSTNAME="$2"; shift 2 ;;
    -h|--help)            usage ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Root/sudo check
if [[ $EUID -eq 0 ]]; then
  echo "ERROR: Do not run as root. Run as regular user (sudo will be used internally)." >&2
  exit 1
fi
if ! sudo -v 2>/dev/null; then
  echo "ERROR: This script requires sudo privileges." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/../scripts"

echo "=== remote-dev-server: Debian install ==="
echo "User: ${USERNAME}"

# Prerequisity
echo "--- Installing prerequisites ---"
sudo apt-get update
sudo apt-get install -y curl ca-certificates gnupg git

# Docker
echo "--- Installing Docker ---"
sudo "${SCRIPTS_DIR}/docker.sh" "$USERNAME"

# Tailscale (only if --tailscale was provided)
if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
  echo "--- Installing Tailscale ---"
  sudo "${SCRIPTS_DIR}/tailscale.sh" "$TAILSCALE_AUTH_KEY" "$TAILSCALE_HOSTNAME"
else
  echo "--- Skipping Tailscale (use --tailscale KEY to install) ---"
fi

# Portainer
echo "--- Installing Portainer ---"
sudo "${SCRIPTS_DIR}/portainer.sh"

# Shared volumes
echo "--- Creating shared volumes ---"
sudo "${SCRIPTS_DIR}/shared-volumes.sh" "$USERNAME"

echo ""
echo "=== Done! ==="
echo "Portainer: https://$(hostname):9443"
echo ""
echo "IMPORTANT: Re-login or run 'newgrp docker' to use Docker without sudo."
