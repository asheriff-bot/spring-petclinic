#!/usr/bin/env bash
# Orchestrate the full DevOps stack setup:
#   02-start-stack.sh                 — pull images and start Jenkins + SonarQube
#   04-configure-jenkins-pipeline.sh  — create the Build job and SCM poll trigger
#   05-configure-sonarqube-jenkins.sh — wire SonarQube token + webhook into Jenkins
#   07-install-vm-prerequisites.sh    — install Vagrant + hypervisor (QEMU/VirtualBox)
#   08-provision-vm.sh                — boot the production-web-server VM
#   09-configure-ansible-control.sh   — start ansible-control and wire it to the VM
#
# After this script completes, trigger a Jenkins build to produce the jar, then
# run ./devops/scripts/10-deploy-app.sh to deploy it to the VM.
#
# Usage:
#   ./devops/scripts/pipeline-setup-main.sh
#
# All env-var overrides accepted by the child scripts are passed through
# (REPO_URL, BRANCH, SONAR_TOKEN, VM_PROVIDER, APP_HOST_PORT, etc.).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Helpers ───────────────────────────────────────────────────────────────────

step() { echo; echo "════════════════════════════════════════"; echo "  $*"; echo "════════════════════════════════════════"; }
ok()   { echo "[ok] $*"; }
fail() { echo "[error] $*" >&2; }

run_step() {
  local label="$1"
  local script="$2"

  step "$label"
  if bash "$script"; then
    ok "$label — done"
  else
    local exit_code=$?
    fail "$label failed (exit $exit_code)"
    fail "Aborting — fix the error above and re-run this script."
    fail "Already-completed steps are idempotent and safe to repeat."
    exit "$exit_code"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

echo
echo "┌─────────────────────────────────────────┐"
echo "│   spring-petclinic  DevOps stack setup   │"
echo "└─────────────────────────────────────────┘"

run_step "Step 1 — Start stack (Jenkins + SonarQube)" \
  "$SCRIPT_DIR/02-start-stack.sh"

run_step "Step 2 — Configure Jenkins pipeline" \
  "$SCRIPT_DIR/04-configure-jenkins-pipeline.sh"

run_step "Step 3 — Wire SonarQube into Jenkins" \
  "$SCRIPT_DIR/05-configure-sonarqube-jenkins.sh"

step "Waiting for monitoring services..."

for i in $(seq 1 60); do
  if curl -sf http://localhost:9090/-/healthy >/dev/null && \
     curl -sf http://localhost:3000/api/health >/dev/null; then
    ok "Monitoring services are ready"
    break
  fi
  sleep 2
done

run_step "Step 3.5 — Configure monitoring (Prometheus + Grafana)" \
  "$SCRIPT_DIR/configure-monitoring.sh"
run_step "Step 4 — Install VM prerequisites (Vagrant + hypervisor)" \
  "$SCRIPT_DIR/07-install-vm-prerequisites.sh"

run_step "Step 5 — Provision production VM" \
  "$SCRIPT_DIR/08-provision-vm.sh"

run_step "Step 6 — Configure Ansible control node" \
  "$SCRIPT_DIR/09-configure-ansible-control.sh"

echo
echo "┌─────────────────────────────────────────┐"
echo "│   Setup complete                         │"
echo "└─────────────────────────────────────────┘"
echo
echo "  Jenkins:   http://localhost:8081"
echo "  SonarQube: http://localhost:9000"
echo
echo "  Infrastructure is ready. To deploy the app:"
echo "    1. Trigger a Jenkins build:  http://localhost:8081/job/Build/build"
echo "       (or push a commit — the SCM poll trigger is active)"
echo "    2. Once Jenkins completes, deploy manually if needed:"
echo "       ./devops/scripts/10-deploy-app.sh"
echo
echo "  Optional: run a ZAP security baseline scan against the live app:"
echo "    ./devops/scripts/06-run-zap-baseline.sh"
echo
