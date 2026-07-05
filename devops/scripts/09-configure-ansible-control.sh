#!/usr/bin/env bash
# Step 8 — start the ansible-control sidecar and point it at the VM.
#
# Reads `vagrant ssh-config` from devops/vagrant (must already be up — run
# ./08-provision-vm.sh first), rewrites HostName 127.0.0.1 -> host.docker.internal
# (127.0.0.1 there is relative to the host, not the ansible-control container),
# and writes devops/ansible/inventory/hosts.ini + copies the private key into
# devops/ansible/files/vagrant_key (bind-mounted into the container).
#
# Idempotent: safe to re-run after the VM is recreated or its SSH port changes.

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
ANSIBLE_DIR="$DEVOPS_DIR/ansible"

if ! (cd "$VAGRANT_DIR" && vagrant status --machine-readable 2>/dev/null | grep -qE ',state,running(,|$)'); then
  echo "[error] VM is not running — run ./devops/scripts/08-provision-vm.sh first"
  exit 1
fi

echo "[..] starting ansible-control container ..."
cd "$DEVOPS_DIR"
docker compose -f docker-compose.deploy.yml up -d --build

echo "[..] reading vagrant ssh-config ..."
SSH_CONFIG="$(cd "$VAGRANT_DIR" && vagrant ssh-config)"

SSH_HOSTNAME="$(echo "$SSH_CONFIG" | awk '/HostName/{print $2}')"
SSH_PORT="$(echo "$SSH_CONFIG" | awk '/Port /{print $2}')"
SSH_USER="$(echo "$SSH_CONFIG" | awk '/User /{print $2}')"
SSH_KEY="$(echo "$SSH_CONFIG" | awk '/IdentityFile/{print $2}')"

if [ -z "$SSH_HOSTNAME" ] || [ -z "$SSH_PORT" ] || [ -z "$SSH_USER" ] || [ -z "$SSH_KEY" ]; then
  echo "[error] could not parse vagrant ssh-config output:"
  echo "$SSH_CONFIG"
  exit 1
fi

# 127.0.0.1 in ssh-config is relative to the host machine, not the
# ansible-control container — translate to the Docker host-gateway alias.
if [ "$SSH_HOSTNAME" = "127.0.0.1" ] || [ "$SSH_HOSTNAME" = "localhost" ]; then
  ANSIBLE_HOST="host.docker.internal"
else
  ANSIBLE_HOST="$SSH_HOSTNAME"
fi

echo "[ok] VM reachable at ${SSH_USER}@${SSH_HOSTNAME}:${SSH_PORT} (key: $SSH_KEY)"

mkdir -p "$ANSIBLE_DIR/inventory" "$ANSIBLE_DIR/files"
cp "$SSH_KEY" "$ANSIBLE_DIR/files/vagrant_key"
chmod 600 "$ANSIBLE_DIR/files/vagrant_key"

cat > "$ANSIBLE_DIR/inventory/hosts.ini" <<EOF
[webservers]
petclinic-prod ansible_host=${ANSIBLE_HOST} ansible_port=${SSH_PORT} ansible_user=${SSH_USER} ansible_ssh_private_key_file=/ansible/files/vagrant_key ansible_python_interpreter=/usr/bin/python3
EOF

echo "[ok] wrote $ANSIBLE_DIR/inventory/hosts.ini"

echo "[..] verifying connectivity from ansible-control ..."
if docker exec petclinic-ansible-control ansible webservers -m ping -i inventory/hosts.ini; then
  echo "[ok] ansible-control can reach the VM"
else
  echo "[error] ansible ping failed — check devops/ansible/inventory/hosts.ini and that the VM is up"
  exit 1
fi

echo
echo "Next: ./devops/scripts/10-deploy-app.sh"
