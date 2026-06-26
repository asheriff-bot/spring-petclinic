#!/usr/bin/env bash
set -euo pipefail

docker compose -f devops/docker-compose.yml run --rm zap \
  zap-baseline.py \
  -t http://host.docker.internal:8080 \
  -r petclinic-baseline.html
  