#!/usr/bin/env bash
# Step 3 — stop the DevOps stack (Jenkins + SonarQube + Postgres)
#
# Usage:
#   ./03-stop-stack.sh          # stop containers, keep volumes
#   ./03-stop-stack.sh -v       # stop containers and remove volumes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(dirname "$SCRIPT_DIR")"

cd "$DEVOPS_DIR"

echo "[..] stopping petclinic-devops stack ..."
docker compose down "$@"

echo "[ok] stack stopped"
echo "     start again: ./scripts/02-start-stack.sh"
