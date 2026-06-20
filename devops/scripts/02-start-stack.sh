#!/usr/bin/env bash
# Step 2 — pull base images and start Jenkins + SonarQube on petclinic-devops-net

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(dirname "$SCRIPT_DIR")"

echo "[..] ensuring custom network exists ..."
bash "$SCRIPT_DIR/01-create-network.sh"

cd "$DEVOPS_DIR"

echo "[..] pulling base images (jenkins, sonarqube, postgres) ..."
docker compose pull

echo "[..] starting containers ..."
docker compose up -d

echo
echo "Stack started. Useful URLs:"
echo "  Jenkins:   http://localhost:8081"
echo "  SonarQube: http://localhost:9000  (default login admin / admin — change on first use)"
echo
echo "Inspect network:"
echo "  docker network inspect petclinic-devops-net"
