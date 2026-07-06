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
docker compose up -d --remove-orphans

# Inject Prometheus config without needing a host bind mount.
# We wait for the container to exist, docker cp the file in, then restart it.
echo "[..] injecting Prometheus config ..."
PROM_CONFIG="$DEVOPS_DIR/prometheus/prometheus.yml"
if [ ! -f "$PROM_CONFIG" ]; then
  echo "[error] Prometheus config not found at $PROM_CONFIG"
  exit 1
fi

# Wait briefly for the container to appear (compose up -d returns fast).
for i in $(seq 1 10); do
  if docker inspect petclinic-prometheus >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

docker cp "$PROM_CONFIG" petclinic-prometheus:/etc/prometheus/prometheus.yml
docker restart petclinic-prometheus >/dev/null
echo "[ok] Prometheus config installed and container restarted"

echo
echo "Stack started. Useful URLs:"
echo "  Jenkins:   http://localhost:8081"
echo "  SonarQube: http://localhost:9000  (default login admin / admin — change on first use)"
echo
echo "Inspect network:"
echo "  docker network inspect petclinic-devops-net"
