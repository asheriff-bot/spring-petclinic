#!/usr/bin/env bash
# Orchestrate a full DevOps stack teardown (reverse of pipeline-setup-main.sh):
#   11-teardown-vm.sh   — stop ansible-control and halt/destroy the production VM
#   03-stop-stack.sh    — stop Jenkins + SonarQube + Postgres
#
# Usage:
#   ./devops/scripts/teardown-main.sh        # halt VM (keep disk), stop stack (keep volumes)
#   ./devops/scripts/teardown-main.sh -v     # destroy VM entirely, remove Docker volumes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Helpers ───────────────────────────────────────────────────────────────────

step() { echo; echo "════════════════════════════════════════"; echo "  $*"; echo "════════════════════════════════════════"; }
ok()   { echo "[ok] $*"; }
fail() { echo "[error] $*" >&2; }

run_step() {
  local label="$1"
  local script="$2"
  shift 2

  step "$label"
  if bash "$script" "$@"; then
    ok "$label — done"
  else
    local exit_code=$?
    fail "$label failed (exit $exit_code)"
    fail "Continuing with remaining teardown steps..."
    # Don't abort — best-effort teardown should keep going
  fi
}

# ── Flags ─────────────────────────────────────────────────────────────────────

DESTROY_VM=false
REMOVE_VOLUMES=false

for arg in "$@"; do
  case "$arg" in
    -v) DESTROY_VM=true; REMOVE_VOLUMES=true ;;
  esac
done

# ── Main ──────────────────────────────────────────────────────────────────────

echo
echo "┌─────────────────────────────────────────┐"
echo "│  spring-petclinic  DevOps stack teardown │"
echo "└─────────────────────────────────────────┘"

if $DESTROY_VM; then
  echo
  echo "  Mode: FULL DESTROY — VM disk and Docker volumes will be removed"
else
  echo
  echo "  Mode: SOFT STOP — VM disk and Docker volumes are kept"
  echo "  Pass -v to destroy everything: ./devops/scripts/teardown-main.sh -v"
fi

# Step 1 — tear down VM and ansible-control (reverse of steps 5/6/9)
if $DESTROY_VM; then
  run_step "Step 1 — Destroy VM and stop ansible-control" \
    "$SCRIPT_DIR/11-teardown-vm.sh" "-v"
else
  run_step "Step 1 — Halt VM and stop ansible-control" \
    "$SCRIPT_DIR/11-teardown-vm.sh"
fi

# Step 2 — stop the DevOps stack (reverse of step 1)
if $REMOVE_VOLUMES; then
  run_step "Step 2 — Stop DevOps stack and remove volumes (Jenkins + SonarQube + Postgres)" \
    "$SCRIPT_DIR/03-stop-stack.sh" "-v"
else
  run_step "Step 2 — Stop DevOps stack, keep volumes (Jenkins + SonarQube + Postgres)" \
    "$SCRIPT_DIR/03-stop-stack.sh"
fi

echo
echo "┌─────────────────────────────────────────┐"
echo "│   Teardown complete                      │"
echo "└─────────────────────────────────────────┘"
echo

if $DESTROY_VM; then
  echo "  Everything has been removed."
  echo "  To rebuild from scratch: ./devops/scripts/pipeline-setup-main.sh"
else
  echo "  Stack stopped. State is preserved:"
  echo "    • VM disk intact  — resume with: vagrant up  (in devops/vagrant/)"
  echo "    • Docker volumes  — resume with: ./devops/scripts/02-start-stack.sh"
  echo
  echo "  To fully destroy: ./devops/scripts/teardown-main.sh -v"
fi
echo
