# VM + Ansible Deployment Setup — spring-petclinic

Adds a CD leg on top of the existing Jenkins + SonarQube stack: a real VM
standing in as the "production web server," and Ansible (run from a
dedicated `ansible-control` sidecar container) to deploy the built jar to it
as a systemd service.

Everything here is additive — it does not modify `devops/docker-compose.yml`,
`devops/scripts/01-05*.sh`, or anything else in the existing CI stack.

## Why a VM instead of another container

The assignment calls for a "production web server" VM, not just another
container. Since Jenkins/SonarQube already run as Docker containers on this
host, the VM is deliberately a different kind of thing — provisioned by
Vagrant, reached over SSH — so the deploy step exercises a real
infrastructure boundary (network, SSH, systemd) rather than another
`docker exec`.

## One-time setup

From repo root:

```bash
./devops/scripts/07-install-vm-prerequisites.sh   # detects OS/arch, installs a hypervisor + Vagrant if missing
./devops/scripts/08-provision-vm.sh                # vagrant up, waits for SSH
./devops/scripts/09-configure-ansible-control.sh   # starts ansible-control, wires up the inventory + SSH key
```

`06` picks the hypervisor per host so this works wherever the repo is
cloned:

| Host | Provider | Box |
|------|----------|-----|
| Apple Silicon (macOS arm64) | Vagrant + QEMU (`vagrant-qemu` plugin) | `perk/ubuntu-2204-arm64` |
| Intel Mac / Linux x86_64 | Vagrant + VirtualBox | `generic/ubuntu2204` |
| Linux arm64 | Vagrant + QEMU | `perk/ubuntu-2204-arm64` |

VirtualBox has no real arm64-Linux-guest support on Apple Silicon (only
slow/beta x86 emulation), which is why Apple Silicon hosts use QEMU (Apple's
Hypervisor.framework) instead — same VM behavior, different provider.
Override the pick with `VM_PROVIDER` / `VM_BOX` env vars before running `06`.

## Deploying

```bash
./devops/scripts/10-deploy-app.sh
```

Builds the jar (if `target/*.jar` isn't already there), copies it into
`ansible-control`, and runs `playbooks/deploy.yml`, which:

- installs `openjdk-17-jre-headless` (matches `pom.xml`'s `java.version`)
- creates a dedicated `petclinic` system user
- copies the jar to `/opt/petclinic/spring-petclinic.jar`
- templates and (re)starts a `petclinic.service` systemd unit

The app is reachable at `http://localhost:8080` (or whatever `APP_HOST_PORT`
was set to before `07-provision-vm.sh`) after a successful run — Jenkins is
`8081`, SonarQube is `9000`.

This same script is what the Jenkinsfile's **Deploy** stage calls, so a
manual deploy and a CI-triggered deploy do exactly the same thing.

## Tearing down

```bash
./devops/scripts/11-teardown-vm.sh       # stop ansible-control, halt the VM (disk kept)
./devops/scripts/11-teardown-vm.sh -v    # also destroy the VM entirely
```

## Known limitations

- `06` installs *packages* (via Homebrew or apt) — it assumes Homebrew (macOS)
  or `apt-get` (Linux) is already present.
- Running a real VM needs nested virtualization. This won't work inside
  another VM or most containerized CI runners — an inherent limitation of
  using a real VM rather than a container as the deploy target.
- The `perk/ubuntu-2204-arm64` box's availability on Vagrant Cloud is
  best-effort; if `vagrant up` 404s on the box, override `VM_BOX` with an
  alternative arm64 box.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `06` fails with "Homebrew not found" | Install Homebrew (macOS) or ensure `apt-get` is on PATH (Linux), then re-run |
| VirtualBox install needs kernel extension approval | System Settings → Privacy & Security → allow the Oracle extension, then re-run `06` |
| `07` times out waiting for SSH | `cd devops/vagrant && vagrant up --provider=$VM_PROVIDER` manually to see the full boot log |
| `08` fails to parse `vagrant ssh-config` | Confirm the VM is running: `cd devops/vagrant && vagrant status` |
| Ansible ping fails | Re-run `./devops/scripts/09-configure-ansible-control.sh` (regenerates inventory + key) |
| `09` deploy fails on "container not found" | Run `./devops/scripts/09-configure-ansible-control.sh` first |
| App not reachable at `:8080` | `cd devops/vagrant && vagrant ssh -c "systemctl status petclinic"` |
