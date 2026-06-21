#!/usr/bin/env bash
# Install SonarQube Jenkins plugin and register the SonarQube server
# Required for withSonarQubeEnv + waitForQualityGate in the pipeline

set -euo pipefail

SONAR_NAME="${SONAR_NAME:-SonarQube}"
SONAR_URL="${SONAR_URL:-http://sonarqube:9000}"
CREDENTIAL_ID="${CREDENTIAL_ID:-sonarqube-system-token}"

echo "[..] installing SonarQube plugin in Jenkins ..."
docker exec petclinic-jenkins jenkins-plugin-cli --plugins "sonar"

echo "[..] writing SonarQube server configuration ..."
CONFIG=$(cat <<EOF
<?xml version='1.1' encoding='UTF-8'?>
<hudson.plugins.sonar.SonarGlobalConfiguration plugin="sonar">
  <installations>
    <hudson.plugins.sonar.SonarInstallation>
      <name>${SONAR_NAME}</name>
      <serverUrl>${SONAR_URL}</serverUrl>
      <credentialsId>${CREDENTIAL_ID}</credentialsId>
      <serverAuthenticationToken>${CREDENTIAL_ID}</serverAuthenticationToken>
      <messagingTimeout>300</messagingTimeout>
      <disabled>false</disabled>
    </hudson.plugins.sonar.SonarInstallation>
  </installations>
  <buildWrapperEnabled>true</buildWrapperEnabled>
</hudson.plugins.sonar.SonarGlobalConfiguration>
EOF
)

TMPFILE="$(mktemp)"
echo "$CONFIG" > "$TMPFILE"
docker cp "$TMPFILE" "petclinic-jenkins:/var/jenkins_home/hudson.plugins.sonar.SonarGlobalConfiguration.xml"
rm -f "$TMPFILE"

echo "[..] restarting Jenkins to load SonarQube plugin ..."
docker restart petclinic-jenkins >/dev/null

echo "[..] waiting for Jenkins ..."
for i in $(seq 1 30); do
  if curl -sf -o /dev/null http://localhost:8081/login; then
    echo "[ok] SonarQube plugin configured (installation: ${SONAR_NAME})"
    echo "     next: ./scripts/04-configure-jenkins-pipeline.sh && Build Now"
    exit 0
  fi
  sleep 3
done

echo "[warn] Jenkins may still be starting — check http://localhost:8081"
exit 0
