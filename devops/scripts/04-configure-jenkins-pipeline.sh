#!/usr/bin/env bash
# Configure the Jenkins Build job with an SCM-backed pipeline and auto-registered poll trigger.
# The trigger is registered via a Groovy init script that runs on every Jenkins startup —
# no manual "Build Now" click required.

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/asheriff-bot/spring-petclinic.git}"
BRANCH="${BRANCH:-main}"
JOB_NAME="${JOB_NAME:-Build}"
POLL_SPEC="${POLL_SPEC:-* * * * *}" # Increase to 5 minutes when ready to go to production

# ── 1. Wait for Jenkins ──────────────────────────────────────────────────────
wait_for_jenkins() {
  echo "[..] waiting for Jenkins ..."
  for i in $(seq 1 40); do
    if curl -sf -o /dev/null http://localhost:8081/login; then
      echo "[ok] Jenkins is up"
      return 0
    fi
    sleep 5
  done
  echo "[error] Jenkins did not start in time"
  exit 1
}

wait_for_jenkins

# ── 2. Install required plugins ──────────────────────────────────────────────
REQUIRED_PLUGINS=(
  workflow-aggregator
  git
  sonar
  timestamper
  junit
)

echo "[..] installing required Jenkins plugins ..."
docker exec petclinic-jenkins jenkins-plugin-cli \
  --plugins "${REQUIRED_PLUGINS[*]}" \
  --verbose 2>&1 | grep -E "^(Installing|Skipping|ERROR|Done)" || true

# ── 3. Write job config.xml ──────────────────────────────────────────────────
# Uses CpsScmFlowDefinition so the job has a real SCM attached (required for
# poll-based triggering). The Jenkinsfile is read from the repo at build time.
JOB_CONFIG=$(cat <<EOF
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@1571.1580.v18e46842c125">
  <description>CI pipeline for spring-petclinic — build, test, SonarQube</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <jenkins.model.BuildDiscarderProperty>
      <strategy class="hudson.tasks.LogRotator">
        <daysToKeep>-1</daysToKeep>
        <numToKeep>10</numToKeep>
        <artifactDaysToKeep>-1</artifactDaysToKeep>
        <artifactNumToKeep>-1</artifactNumToKeep>
      </strategy>
    </jenkins.model.BuildDiscarderProperty>
    <org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
      <triggers>
        <hudson.triggers.SCMTrigger>
          <spec>${POLL_SPEC}</spec>
          <ignorePostCommitHooks>false</ignorePostCommitHooks>
        </hudson.triggers.SCMTrigger>
      </triggers>
    </org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps@4331.v9d06ed4658ff">
    <scm class="hudson.plugins.git.GitSCM" plugin="git@5.10.1">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>${REPO_URL}</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/${BRANCH}</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <submoduleCfg class="empty-list"/>
      <extensions/>
    </scm>
    <scriptPath>Jenkinsfile</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
EOF
)

echo "[..] writing job config ..."
docker exec petclinic-jenkins mkdir -p "/var/jenkins_home/jobs/${JOB_NAME}"
echo "$JOB_CONFIG" | docker exec -i petclinic-jenkins tee "/var/jenkins_home/jobs/${JOB_NAME}/config.xml" > /dev/null
docker exec petclinic-jenkins chown -R jenkins:jenkins "/var/jenkins_home/jobs/${JOB_NAME}"

# ── 4. Drop a Groovy init script to register the trigger on every startup ────
# Jenkins runs all *.groovy files in init.groovy.d/ before marking itself ready.
# This script looks up the job, finds the SCMTrigger from PipelineTriggersJobProperty,
# and calls start() on it — which is the call that actually schedules the poll.
INIT_SCRIPT=$(cat <<'GROOVY'
import hudson.triggers.SCMTrigger
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty

def jobName = System.getenv('JENKINS_POLL_JOB') ?: 'Build'

jenkins.model.Jenkins.instance.allItems(WorkflowJob).each { job ->
  if (job.name != jobName) return

  def triggersProp = job.getProperty(PipelineTriggersJobProperty)
  if (triggersProp == null) {
    println "[init] ${job.name}: no PipelineTriggersJobProperty found — skipping"
    return
  }

  triggersProp.triggers.each { trigger ->
    if (trigger instanceof SCMTrigger) {
      trigger.start(job, true)
      println "[init] ${job.name}: SCMTrigger started (spec: ${trigger.spec})"
    }
  }
}
GROOVY
)

echo "[..] installing trigger-registration init script ..."
docker exec petclinic-jenkins mkdir -p /var/jenkins_home/init.groovy.d
echo "$INIT_SCRIPT" | docker exec -i petclinic-jenkins tee /var/jenkins_home/init.groovy.d/register-scm-trigger.groovy > /dev/null
docker exec petclinic-jenkins chown -R jenkins:jenkins /var/jenkins_home/init.groovy.d

# ── 5. Restart Jenkins so both the job config and init script take effect ────
echo "[..] restarting Jenkins ..."
docker restart petclinic-jenkins > /dev/null
wait_for_jenkins

echo "[ok] Done. Open http://localhost:8081/job/${JOB_NAME}/polling to verify the Git Polling Log."
