#!/usr/bin/env bash
# Step 6 — detect host OS/arch and make sure a hypervisor + Vagrant are
# available to run the production-web-server VM. Idempotent: every install
# is preceded by a "do we already have this" check.
#
# Apple Silicon (Darwin/arm64) has no real VirtualBox arm64-Linux-guest
# support (only slow/beta x86 emulation), so on that combo we use Vagrant's
# QEMU provider (Apple's Hypervisor.framework) instead. Everywhere else
# (Intel Mac, Linux x86_64) VirtualBox runs the guest natively.
#
# Writes the chosen provider/box/sizing to devops/vagrant/.detected-env,
# which 08-provision-vm.sh sources before `vagrant up`.
#
# Override any pick via env vars: VM_PROVIDER, VM_BOX, VM_MEMORY, VM_CPUS.

set -euo pipefail

# Homebrew's bin dir isn't always on PATH (non-login/non-interactive shells
# don't source .zprofile) even when brew and its packages are installed —
# make sure brew-installed tools are still found regardless of caller shell.
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

OS="$(uname -s)"
ARCH="$(uname -m)"

VM_MEMORY="${VM_MEMORY:-2048}"
VM_CPUS="${VM_CPUS:-2}"

echo "[..] detected host: OS=$OS ARCH=$ARCH"

if [ "$OS" = "Darwin" ] && { [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; }; then
  VM_PROVIDER="${VM_PROVIDER:-qemu}"
  VM_BOX="${VM_BOX:-perk/ubuntu-2204-arm64}"
elif [ "$OS" = "Linux" ] && { [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; }; then
  VM_PROVIDER="${VM_PROVIDER:-qemu}"
  VM_BOX="${VM_BOX:-perk/ubuntu-2204-arm64}"
else
  VM_PROVIDER="${VM_PROVIDER:-virtualbox}"
  VM_BOX="${VM_BOX:-generic/ubuntu2204}"
fi

echo "[ok] provider=$VM_PROVIDER box=$VM_BOX memory=${VM_MEMORY}MB cpus=$VM_CPUS"

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# ── macOS (Homebrew) ─────────────────────────────────────────────────────────
install_macos() {
  if ! has_cmd brew; then
    echo "[..] Homebrew not found — installing it non-interactively ..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi

    if ! has_cmd brew; then
      echo "[error] Homebrew install did not complete (this can happen if Xcode Command Line Tools"
      echo "        need interactive install — run 'xcode-select --install' and re-run this script)."
      exit 1
    fi
    echo "[ok] Homebrew installed"
  fi

  if [ "$VM_PROVIDER" = "qemu" ]; then
    if has_cmd qemu-system-aarch64 || has_cmd qemu-system-x86_64; then
      echo "[ok] qemu already installed"
    else
      echo "[..] installing qemu ..."
      brew install qemu
    fi
  else
    if has_cmd VBoxManage; then
      echo "[ok] VirtualBox already installed"
    else
      echo "[..] installing VirtualBox (you may need to approve a kernel extension"
      echo "     in System Settings → Privacy & Security, then re-run this script) ..."
      brew install --cask virtualbox
    fi
  fi

  if has_cmd vagrant; then
    echo "[ok] vagrant already installed"
  else
    echo "[..] installing vagrant (cask) ..."
    brew install --cask vagrant
  fi
}

# ── Linux (apt) ───────────────────────────────────────────────────────────────
install_linux() {
  if ! has_cmd apt-get; then
    echo "[error] no apt-get found. Install ${VM_PROVIDER} + vagrant manually for this distro, then re-run."
    exit 1
  fi

  if [ "$VM_PROVIDER" = "qemu" ]; then
    if has_cmd qemu-system-aarch64 || has_cmd qemu-system-x86_64; then
      echo "[ok] qemu already installed"
    else
      echo "[..] installing qemu ..."
      sudo apt-get update
      sudo apt-get install -y qemu-system qemu-utils
    fi
  else
    if has_cmd VBoxManage; then
      echo "[ok] VirtualBox already installed"
    else
      echo "[..] installing VirtualBox ..."
      sudo apt-get update
      sudo apt-get install -y virtualbox
    fi
  fi

  if has_cmd vagrant; then
    echo "[ok] vagrant already installed"
  else
    echo "[..] installing vagrant (HashiCorp apt repo) ..."
    curl -fsSL https://apt.releases.hashicorp.com/gpg \
      | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
      | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y vagrant
  fi
}

case "$OS" in
  Darwin) install_macos ;;
  Linux) install_linux ;;
  *)
    echo "[error] unsupported host OS '$OS' — install ${VM_PROVIDER} + vagrant manually."
    exit 1
    ;;
esac

if [ "$VM_PROVIDER" = "qemu" ]; then
  if vagrant plugin list 2>/dev/null | grep -q '^vagrant-qemu '; then
    echo "[ok] vagrant-qemu plugin already installed"
  else
    echo "[..] installing vagrant-qemu plugin ..."
    vagrant plugin install vagrant-qemu
  fi
fi

mkdir -p "$VAGRANT_DIR"
cat > "$DETECTED_ENV" <<EOF
VM_PROVIDER=$VM_PROVIDER
VM_BOX=$VM_BOX
VM_MEMORY=$VM_MEMORY
VM_CPUS=$VM_CPUS
EOF

echo "[ok] wrote $DETECTED_ENV"
echo
echo "Next: ./devops/scripts/07-provision-vm.sh"
