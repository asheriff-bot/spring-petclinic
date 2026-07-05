# Ansible control node for deploying spring-petclinic to the production VM.
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ansible-core \
       openssh-client \
       python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /ansible
CMD ["sleep", "infinity"]
