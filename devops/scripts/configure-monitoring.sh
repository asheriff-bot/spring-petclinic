#!/usr/bin/env bash
set -euo pipefail

JENKINS_CONTAINER="${JENKINS_CONTAINER:-petclinic-jenkins}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"

wait_for_url() {
  local url="$1"
  local label="$2"
  local seconds="${3:-60}"

  for _ in $(seq 1 "$seconds"); do
    if curl -sf "$url" >/dev/null; then
      echo "[ok] $label is up"
      return 0
    fi
    sleep 1
  done

  echo "[error] $label did not become ready in time"
  exit 1
}

echo "[..] verifying Jenkins container ..."
docker inspect "$JENKINS_CONTAINER" >/dev/null

echo "[..] installing Prometheus plugin in Jenkins ..."
docker exec "$JENKINS_CONTAINER" jenkins-plugin-cli --plugins "prometheus"

echo "[..] restarting Jenkins ..."
docker restart "$JENKINS_CONTAINER" >/dev/null

echo "[..] waiting for Jenkins ..."
wait_for_url "http://localhost:8081/login" "Jenkins" 60

echo "[..] waiting for Jenkins metrics endpoint ..."
wait_for_url "http://localhost:8081/prometheus" "Jenkins metrics endpoint" 30

echo "[..] verifying Prometheus target ..."
for _ in $(seq 1 30); do
  if curl -sf "$PROMETHEUS_URL/api/v1/query?query=up%7Bjob%3D%22jenkins%22%7D" | grep -q '"value".*"1"'; then
    echo "[ok] Prometheus is scraping Jenkins"
    echo "[ok] Monitoring setup complete"
    echo "    Prometheus: $PROMETHEUS_URL"
    echo "    Grafana:    $GRAFANA_URL"
    exit 0
  fi
  sleep 2
done

echo "[error] Prometheus is not scraping Jenkins"
exit 1
