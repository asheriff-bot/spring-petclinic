#!/usr/bin/env bash
# Wire SonarQube into Jenkins end-to-end:
#   1. Install the SonarQube Jenkins plugin
#   2. Provision a SonarQube user token via REST API (or use $SONAR_TOKEN if set)
#   3. Register the SonarQube → Jenkins webhook (for waitForQualityGate)
#   4. Inject the token into Jenkins as a Secret-text credential
#   5. Register the SonarQube server in Jenkins global config
#   6. Restart Jenkins once and verify
#
# Idempotent: revokes any existing token of the same name, replaces the
# Jenkins credential if it already exists, overwrites the server config.
#
# Override defaults via env vars:
#   SONAR_NAME, SONAR_URL (server-side, as Jenkins sees it),
#   SONAR_PUBLIC_URL (host-side, for our REST calls),
#   SONAR_ADMIN_USER, SONAR_ADMIN_PASSWORD,
#   SONAR_TOKEN_NAME, SONAR_TOKEN (skip provisioning if set),
#   JENKINS_CONTAINER, CREDENTIAL_ID,
#   SONAR_WEBHOOK_NAME, SONAR_WEBHOOK_URL (Jenkins URL as SonarQube sees it)

set -euo pipefail

SONAR_NAME="${SONAR_NAME:-SonarQube}"
SONAR_URL="${SONAR_URL:-http://sonarqube:9000}"
SONAR_PUBLIC_URL="${SONAR_PUBLIC_URL:-http://localhost:9000}"
SONAR_ADMIN_USER="${SONAR_ADMIN_USER:-admin}"
SONAR_ADMIN_PASSWORD="${SONAR_ADMIN_PASSWORD:-admin}"
SONAR_TOKEN_NAME="${SONAR_TOKEN_NAME:-jenkins}"
SONAR_TOKEN="${SONAR_TOKEN:-}"

# Webhook from SonarQube → Jenkins, used by waitForQualityGate.
# URL must be reachable from inside the SonarQube container, so we use the
# Jenkins compose service name on petclinic-devops-net (internal port 8080).
SONAR_WEBHOOK_NAME="${SONAR_WEBHOOK_NAME:-Jenkins}"
SONAR_WEBHOOK_URL="${SONAR_WEBHOOK_URL:-http://jenkins:8080/sonarqube-webhook/}"

JENKINS_CONTAINER="${JENKINS_CONTAINER:-petclinic-jenkins}"
CREDENTIAL_ID="${CREDENTIAL_ID:-sonarqube-system-token}"

# ── 1. Sanity checks ─────────────────────────────────────────────────────────
if ! docker inspect "$JENKINS_CONTAINER" >/dev/null 2>&1; then
  echo "[error] Jenkins container '$JENKINS_CONTAINER' not found — run ./scripts/02-start-stack.sh"
  exit 1
fi

# ── 2. Install SonarQube plugin ──────────────────────────────────────────────
echo "[..] installing SonarQube plugin in Jenkins ..."
docker exec "$JENKINS_CONTAINER" jenkins-plugin-cli --plugins "sonar"

# ── 3. Obtain a SonarQube token (provision via API, or use caller-supplied) ──
if [ -n "$SONAR_TOKEN" ]; then
  echo "[ok] using caller-supplied SonarQube token (\$SONAR_TOKEN set)"
else
  echo "[..] waiting for SonarQube at $SONAR_PUBLIC_URL ..."
  for i in $(seq 1 40); do
    status="$(curl -s "$SONAR_PUBLIC_URL/api/system/status" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p' || true)"
    if [ "$status" = "UP" ]; then
      echo "[ok] SonarQube is UP"
      break
    fi
    sleep 3
    if [ "$i" -eq 40 ]; then
      echo "[error] SonarQube did not become UP in time"
      exit 1
    fi
  done

  auth_response="$(curl -s -u "$SONAR_ADMIN_USER:$SONAR_ADMIN_PASSWORD" \
    "$SONAR_PUBLIC_URL/api/authentication/validate")"
  case "$auth_response" in
    *'"valid":true'*) : ;;
    *)
      echo "[error] SonarQube admin login failed for user '$SONAR_ADMIN_USER'"
      echo "        response: $auth_response"
      echo "        set SONAR_ADMIN_PASSWORD env var (default 'admin')"
      exit 1
      ;;
  esac

  echo "[..] revoking any existing SonarQube token named '$SONAR_TOKEN_NAME' ..."
  curl -s -o /dev/null -u "$SONAR_ADMIN_USER:$SONAR_ADMIN_PASSWORD" \
    -X POST "$SONAR_PUBLIC_URL/api/user_tokens/revoke" \
    --data-urlencode "name=$SONAR_TOKEN_NAME" || true

  echo "[..] generating SonarQube token '$SONAR_TOKEN_NAME' ..."
  GEN_RESPONSE="$(curl -s -u "$SONAR_ADMIN_USER:$SONAR_ADMIN_PASSWORD" \
    -X POST "$SONAR_PUBLIC_URL/api/user_tokens/generate" \
    --data-urlencode "name=$SONAR_TOKEN_NAME")"

  SONAR_TOKEN="$(echo "$GEN_RESPONSE" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
  if [ -z "$SONAR_TOKEN" ]; then
    echo "[error] failed to extract token from response: $GEN_RESPONSE"
    exit 1
  fi
  echo "[ok] token generated (length ${#SONAR_TOKEN})"
fi

# ── 4. Configure SonarQube webhook → Jenkins (for waitForQualityGate) ────────
# Without this, the SonarQube Compute Engine never POSTs to Jenkins when
# analysis completes, and waitForQualityGate just sits until its timeout.
echo "[..] removing any existing SonarQube webhook named '$SONAR_WEBHOOK_NAME' ..."
EXISTING_HOOKS="$(curl -s -u "$SONAR_ADMIN_USER:$SONAR_ADMIN_PASSWORD" \
  "$SONAR_PUBLIC_URL/api/webhooks/list")"

# Pull out the "key" of every webhook whose "name" matches SONAR_WEBHOOK_NAME.
# Parses the flat JSON object stream: ...{"key":"abc","name":"Jenkins",...}...
EXISTING_KEYS="$(echo "$EXISTING_HOOKS" \
  | tr ',' '\n' \
  | awk -v name="\"name\":\"$SONAR_WEBHOOK_NAME\"" '
      /"key":/ { gsub(/.*"key":"|".*/, ""); key=$0; next }
      $0 == name && key { print key; key="" }
    ' || true)"

if [ -n "$EXISTING_KEYS" ]; then
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    curl -s -o /dev/null -u "$SONAR_ADMIN_USER:$SONAR_ADMIN_PASSWORD" \
      -X POST "$SONAR_PUBLIC_URL/api/webhooks/delete" \
      --data-urlencode "webhook=$key" || true
    echo "[ok] deleted webhook key=$key"
  done <<< "$EXISTING_KEYS"
else
  echo "[ok] no existing webhook to remove"
fi

echo "[..] creating SonarQube webhook '$SONAR_WEBHOOK_NAME' → $SONAR_WEBHOOK_URL ..."
HOOK_RESPONSE="$(curl -s -u "$SONAR_ADMIN_USER:$SONAR_ADMIN_PASSWORD" \
  -X POST "$SONAR_PUBLIC_URL/api/webhooks/create" \
  --data-urlencode "name=$SONAR_WEBHOOK_NAME" \
  --data-urlencode "url=$SONAR_WEBHOOK_URL")"

case "$HOOK_RESPONSE" in
  *'"webhook"'*'"key"'*) echo "[ok] webhook registered" ;;
  *)
    echo "[error] failed to create SonarQube webhook"
    echo "        response: $HOOK_RESPONSE"
    exit 1
    ;;
esac

# ── 5. Stage a one-shot Groovy init script + the token inside Jenkins ────────
# The init script runs at startup with full Jenkins privileges, encrypts the
# secret correctly via hudson.util.Secret, adds the credential, then deletes
# both itself and the token file so nothing sensitive lingers on disk.
TOKEN_PATH_IN_CONTAINER="/var/jenkins_home/.sonarqube-token"
INIT_SCRIPT_NAME="install-sonarqube-credential.groovy"
INIT_SCRIPT_PATH="/var/jenkins_home/init.groovy.d/${INIT_SCRIPT_NAME}"

INIT_SCRIPT=$(cat <<GROOVY
import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.domains.Domain
import org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl
import hudson.util.Secret

def credId = '${CREDENTIAL_ID}'
def tokenFile = new File('${TOKEN_PATH_IN_CONTAINER}')
def selfFile  = new File('${INIT_SCRIPT_PATH}')

if (!tokenFile.exists()) {
  println "[init] no token file at \${tokenFile} — skipping credential install"
  return
}

def token = tokenFile.text.trim()
def provider = SystemCredentialsProvider.getInstance()
def store = provider.getStore()
def domain = Domain.global()

// remove any existing credential with the same id so re-runs replace cleanly
store.getCredentials(domain).findAll { it.id == credId }.each {
  store.removeCredentials(domain, it)
  println "[init] removed existing credential '\${credId}'"
}

def cred = new StringCredentialsImpl(
  CredentialsScope.GLOBAL,
  credId,
  'SonarQube authentication token (auto-provisioned)',
  Secret.fromString(token)
)
store.addCredentials(domain, cred)
provider.save()
println "[init] installed credential '\${credId}'"

// scrub the token file and remove this init script so it does not re-run
tokenFile.delete()
selfFile.delete()
GROOVY
)

echo "[..] staging credential install script in $JENKINS_CONTAINER ..."
docker exec "$JENKINS_CONTAINER" mkdir -p /var/jenkins_home/init.groovy.d

# Write token via stdin so it never appears in `ps` listings
printf '%s' "$SONAR_TOKEN" | docker exec -i "$JENKINS_CONTAINER" \
  sh -c "umask 077 && cat > '$TOKEN_PATH_IN_CONTAINER'"

echo "$INIT_SCRIPT" | docker exec -i "$JENKINS_CONTAINER" \
  tee "$INIT_SCRIPT_PATH" >/dev/null

docker exec "$JENKINS_CONTAINER" chown jenkins:jenkins \
  "$TOKEN_PATH_IN_CONTAINER" "$INIT_SCRIPT_PATH"

# ── 6. Write SonarQube server config ─────────────────────────────────────────
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
docker cp "$TMPFILE" "${JENKINS_CONTAINER}:/var/jenkins_home/hudson.plugins.sonar.SonarGlobalConfiguration.xml"
rm -f "$TMPFILE"

# ── 7. Single restart so plugin + credential + server config all take effect ─
echo "[..] restarting Jenkins ..."
docker restart "$JENKINS_CONTAINER" >/dev/null

echo "[..] waiting for Jenkins ..."
for i in $(seq 1 40); do
  if curl -sf -o /dev/null http://localhost:8081/login; then
    echo "[ok] Jenkins is up"
    break
  fi
  sleep 5
  if [ "$i" -eq 40 ]; then
    echo "[error] Jenkins did not start in time"
    exit 1
  fi
done

# ── 8. Verify ────────────────────────────────────────────────────────────────
# Give Jenkins a beat to flush credentials.xml after the init script runs.
sleep 3
if docker exec "$JENKINS_CONTAINER" grep -q "<id>${CREDENTIAL_ID}</id>" \
     /var/jenkins_home/credentials.xml; then
  echo "[ok] credential '${CREDENTIAL_ID}' is present in Jenkins"
else
  echo "[error] credential not found in credentials.xml — check the init log:"
  echo "        docker logs $JENKINS_CONTAINER | grep '\[init\]'"
  exit 1
fi

# Belt-and-braces: make sure the token file is gone.
docker exec "$JENKINS_CONTAINER" rm -f "$TOKEN_PATH_IN_CONTAINER" || true

echo
echo "[ok] SonarQube wired into Jenkins (server '${SONAR_NAME}', credential '${CREDENTIAL_ID}')"
echo "     next: ./devops/scripts/04-configure-jenkins-pipeline.sh && Build Now"
