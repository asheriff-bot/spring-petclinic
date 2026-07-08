#!/usr/bin/env bash
# Step 9 — deploy a pre-built spring-petclinic jar to the production VM.
#
# Expects a jar to already exist under target/ — built by Jenkins in the
# Build stage (./mvnw -B -DskipTests package). If no jar is present, the
# script exits with an error rather than attempting a local build.
#
# Jenkins calls this script directly from the Deploy stage, so CI and manual
# deploys go through identical Ansible steps.

set -euo pipefail

# Homebrew's bin dir isn't always on PATH (non-login/non-interactive shells
# don't source .zprofile) even when brew and its packages are installed.
for brew_bin in /opt/homebrew/bin /usr/local/bin; do
  case ":$PATH:" in
    *":$brew_bin:"*) ;;
    *) [ -d "$brew_bin" ] && PATH="$brew_bin:$PATH" ;;
  esac
done
export PATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONTAINER="${CONTAINER:-petclinic-ansible-control}"

cd "$REPO_ROOT"

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "[error] $CONTAINER not found — run ./devops/scripts/09-configure-ansible-control.sh first"
  exit 1
fi

shopt -s nullglob
JARS=(target/spring-petclinic-*.jar)
shopt -u nullglob

if [ "${#JARS[@]}" -eq 0 ]; then
  echo "[error] no jar found under target/ — trigger a Jenkins build first:"
  echo "        http://localhost:8081/job/Build/build"
  echo "        (or push a commit if the SCM poll trigger is active)"
  exit 1
fi

JAR_PATH="${JARS[0]}"
echo "[ok] deploying $JAR_PATH"

echo "[..] copying jar into $CONTAINER ..."
docker cp "$JAR_PATH" "$CONTAINER:/ansible/files/spring-petclinic.jar"

echo "[..] running deploy playbook ..."
docker exec "$CONTAINER" ansible-playbook \
  -i inventory/hosts.ini \
  playbooks/deploy.yml \
  -e jar_src_path=/ansible/files/spring-petclinic.jar

echo "[ok] deploy complete"
