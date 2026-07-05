#!/usr/bin/env bash
# Step 9 — build (if needed) and deploy spring-petclinic to the production VM.
#
# This is the single script both a human on a clean checkout and the
# Jenkinsfile's Deploy stage call — so manual and CI deploys behave
# identically. If target/*.jar already exists (e.g. Jenkins already ran
# `./mvnw -B verify` in an earlier stage) it's reused instead of rebuilt.

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

# ./mvnw needs a local JDK (separate from the JRE Ansible installs on the VM).
# Idempotent check-then-install, same pattern as 07-install-vm-prerequisites.sh.
ensure_local_jdk() {
  if command -v java >/dev/null 2>&1 && java -version >/dev/null 2>&1; then
    return 0
  fi

  case "$(uname -s)" in
    Darwin)
      if ! command -v brew >/dev/null 2>&1; then
        echo "[error] no local JDK and Homebrew not found — install a JDK 17 manually, then re-run"
        exit 1
      fi
      OPENJDK_PREFIX="$(brew --prefix)/opt/openjdk@17"
      if [ ! -d "$OPENJDK_PREFIX" ]; then
        echo "[..] no local JDK found — installing OpenJDK 17 (needed to run ./mvnw) ..."
        brew install openjdk@17
      fi
      export JAVA_HOME="$OPENJDK_PREFIX"
      export PATH="$JAVA_HOME/bin:$PATH"
      ;;
    Linux)
      echo "[..] no local JDK found — installing OpenJDK 17 (needed to run ./mvnw) ..."
      sudo apt-get update
      sudo apt-get install -y openjdk-17-jdk-headless
      ;;
    *)
      echo "[error] unsupported OS for automatic JDK install — install a JDK 17 manually"
      exit 1
      ;;
  esac

  if ! java -version >/dev/null 2>&1; then
    echo "[error] JDK install did not produce a working 'java' on PATH"
    exit 1
  fi
  echo "[ok] local JDK ready: $(java -version 2>&1 | head -1)"
}

shopt -s nullglob
JARS=(target/spring-petclinic-*.jar)
shopt -u nullglob

if [ "${#JARS[@]}" -eq 0 ]; then
  ensure_local_jdk
  echo "[..] no jar in target/ — building ..."
  ./mvnw -B -DskipTests package
  shopt -s nullglob
  JARS=(target/spring-petclinic-*.jar)
  shopt -u nullglob
else
  echo "[ok] reusing existing jar (skip rebuild)"
fi

if [ "${#JARS[@]}" -eq 0 ]; then
  echo "[error] build did not produce a jar under target/"
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
