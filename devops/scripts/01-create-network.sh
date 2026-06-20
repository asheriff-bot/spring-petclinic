#!/usr/bin/env bash
# Step 1 — create the shared bridge network for the DevOps stack
# Run once before docker compose up

set -euo pipefail

NETWORK_NAME="petclinic-devops-net"

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "[ok] network '$NETWORK_NAME' already exists"
  docker network inspect "$NETWORK_NAME" --format '  id={{.Id}}  driver={{.Driver}}'
else
  echo "[..] creating network '$NETWORK_NAME' ..."
  docker network create \
    --driver bridge \
    --label project=spring-petclinic \
    --label env=mini5-devops \
    "$NETWORK_NAME"
  echo "[ok] network created"
fi
