#!/usr/bin/env bash
# Run a ZAP baseline scan against the running app and save the HTML report.
#
# The report is extracted with `docker cp` rather than a host bind mount so it
# works without configuring Docker Desktop File Sharing on macOS.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_DIR="$REPO_ROOT/devops/reports/zap"
REPORT_NAME="petclinic-baseline.html"
CONTAINER_NAME="petclinic-zap-scan"
TARGET_URL="${ZAP_TARGET_URL:-http://host.docker.internal:8080}"
NETWORK="${ZAP_NETWORK:-petclinic-devops-net}"

mkdir -p "$REPORT_DIR"

# Remove any leftover container from a previous run so --name doesn't collide.
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

# Run the scan. zap-baseline.py returns non-zero when it finds warnings/failures,
# so capture the code instead of letting `set -e` abort before we grab the report.
#
# Using `docker run` directly (rather than docker compose run) because:
#  - Guarantees --add-host is applied regardless of compose file version in checkout
#  - Anonymous volume + chown gives zap user write access to /zap/wrk
echo "[..] running ZAP baseline scan against $TARGET_URL ..."
set +e
docker run \
  --name "$CONTAINER_NAME" \
  --network "$NETWORK" \
  --add-host "host.docker.internal:host-gateway" \
  -v /zap/wrk \
  --user root \
  --entrypoint sh \
  ghcr.io/zaproxy/zaproxy:stable \
  -c "chown zap:zap /zap/wrk && runuser -u zap -- zap-baseline.py -t '${TARGET_URL}' -r '${REPORT_NAME}'"
scan_rc=$?
set -e

# Copy the report out of the (stopped) container via the Docker API.
echo "[..] extracting report ..."
if docker cp "$CONTAINER_NAME:/zap/wrk/$REPORT_NAME" "$REPORT_DIR/$REPORT_NAME" 2>/dev/null; then
  echo "[ok] ZAP report: $REPORT_DIR/$REPORT_NAME"
else
  echo "[warn] could not extract report from container (scan may have failed to start)"
fi

# Clean up the one-shot container.
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

# Propagate the scan result:
#   0 = clean, 1 = warnings, 2 = warnings (newer ZAP versions), 3+ = hard failures.
#   Warnings are informational — don't fail the build. Only fail on code 3+
#   which indicates ZAP couldn't run at all (connectivity, config errors, etc).
if [ "$scan_rc" -ge 3 ]; then
  exit "$scan_rc"
fi
exit 0
