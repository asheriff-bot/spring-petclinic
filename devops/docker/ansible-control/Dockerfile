# Ansible control node for deploying spring-petclinic to the production VM.
# Static content (ansible.cfg, playbooks, templates) is baked into the image.
# Dynamic runtime files (SSH key, inventory) are injected via `docker cp` by
# 09-configure-ansible-control.sh — no host bind mounts required.
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ansible-core \
       openssh-client \
       python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /ansible

# Copy static Ansible content at build time so no host path needs to be
# shared with Docker Desktop (avoids the "path not shared" error on macOS).
COPY ansible/ansible.cfg          ./ansible.cfg
COPY ansible/playbooks/           ./playbooks/

CMD ["sleep", "infinity"]
