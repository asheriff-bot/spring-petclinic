#!/usr/bin/env bash
# Step 7 — bring up the production-web-server VM (idempotent: safe to re-run
# against an already-running VM).
#
# Reads provider/box/sizing from devops/vagrant/.detected-env, written by
# ./07-install-vm-prerequisites.sh. Override APP_HOST_PORT to change which
# host port the app (guest :8080) is forwarded to.

set -euo pipefail

# Homebrew's bin dir isn't always on PATH (non-login/non-interactive shells
# don't source .zprofile) even when brew and its packages are installed —
# make sure brew-installed tools (vagrant, qemu-img, ...) are still found.
for brew_bin in /opt/homebrew/bin /usr/local/bin; do
  case ":$PATH:" in
    *":$brew_bin:"*) ;;
    *) [ -d "$brew_bin" ] && PATH="$brew_bin:$PATH" ;;
  esac
done
export PATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAGRANT_DIR="$(dirname "$SCRIPT_DIR")/vagrant"
DETECTED_ENV="$VAGRANT_DIR/.detected-env"

if [ ! -f "$DETECTED_ENV" ]; then
  echo "[error] $DETECTED_ENV not found — run ./devops/scripts/07-install-vm-prerequisites.sh first"
  exit 1
fi

# shellcheck disable=SC1090
source "$DETECTED_ENV"
export VM_PROVIDER VM_BOX VM_MEMORY VM_CPUS
export APP_HOST_PORT="${APP_HOST_PORT:-8080}"

cd "$VAGRANT_DIR"

echo "[..] checking VM status ..."
if vagrant status --machine-readable 2>/dev/null | grep -qE ',state,running(,|$)'; then
  echo "[ok] VM already running"
else
  echo "[..] starting VM (provider=$VM_PROVIDER box=$VM_BOX) — this may take a few minutes on first run ..."
  vagrant up --provider="$VM_PROVIDER"
fi

echo "[..] waiting for SSH to be ready ..."
for i in $(seq 1 30); do
  if vagrant ssh -c "true" >/dev/null 2>&1; then
    echo "[ok] VM is reachable over SSH"
    break
  fi
  sleep 5
  if [ "$i" -eq 30 ]; then
    echo "[error] VM did not become SSH-reachable in time"
    exit 1
  fi
done

echo
echo "VM ready. Useful commands:"
echo "  vagrant ssh        (from $VAGRANT_DIR)"
echo "  vagrant ssh-config (from $VAGRANT_DIR)"
echo
echo "Next: ./devops/scripts/09-configure-ansible-control.sh"
