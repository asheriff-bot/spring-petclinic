#!/usr/bin/env bash
# Step 10 — tear down the deployment stack (ansible-control + VM).
#
# Usage:
#   ./11-teardown-vm.sh          # halt the VM, stop ansible-control (keep VM disk)
#   ./11-teardown-vm.sh -v       # also destroy the VM entirely (vagrant destroy)

set -euo pipefail

# Homebrew's bin dir isn't always on PATH (non-login/non-interactive shells
# don't source .zprofile) even when brew and its packages are installed —
# make sure brew-installed tools (vagrant, ...) are still found.
for brew_bin in /opt/homebrew/bin /usr/local/bin; do
  case ":$PATH:" in
    *":$brew_bin:"*) ;;
    *) [ -d "$brew_bin" ] && PATH="$brew_bin:$PATH" ;;
  esac
done
export PATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_DIR="$(dirname "$SCRIPT_DIR")"
VAGRANT_DIR="$DEVOPS_DIR/vagrant"

cd "$DEVOPS_DIR"
echo "[..] stopping ansible-control ..."
docker compose -f docker-compose.deploy.yml down

cd "$VAGRANT_DIR"
if [ "${1:-}" = "-v" ]; then
  echo "[..] destroying VM ..."
  vagrant destroy -f
  echo "[ok] VM destroyed"
else
  echo "[..] halting VM (disk kept) ..."
  vagrant halt
  echo "[ok] VM halted"
  echo "     destroy entirely: ./scripts/11-teardown-vm.sh -v"
fi
