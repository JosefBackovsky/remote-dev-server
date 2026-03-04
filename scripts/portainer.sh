#!/usr/bin/env bash
set -euo pipefail

# Idempotentní — pokud kontejner existuje, zajistit že běží
if docker ps -a --format '{{.Names}}' | grep -q '^portainer$'; then
  if ! docker ps --format '{{.Names}}' | grep -q '^portainer$'; then
    echo "Portainer is stopped, starting..."
    docker start portainer
  else
    echo "Portainer already running."
  fi
  exit 0
fi

docker volume create portainer_data
docker run -d --name portainer --restart=always \
  -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
