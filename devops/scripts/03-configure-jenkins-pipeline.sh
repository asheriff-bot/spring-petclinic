#!/usr/bin/env bash
# Reconfigure Jenkins "Build" job to use Jenkinsfile from GitHub (Pipeline from SCM)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="${REPO_URL:-https://github.com/asheriff-bot/spring-petclinic.git}"
BRANCH="${BRANCH:-main}"
JOB_NAME="${JOB_NAME:-Build}"

CONFIG=$(cat <<EOF
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
        <removeLastBuild>false</removeLastBuild>
      </strategy>
    </jenkins.model.BuildDiscarderProperty>
    <com.coravy.hudson.plugins.github.GithubProjectProperty plugin="github@1.47.0">
      <projectUrl>${REPO_URL}/</projectUrl>
      <displayName>spring-petclinic</displayName>
    </com.coravy.hudson.plugins.github.GithubProjectProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps@4331.v9d06ed4658ff">
    <scm class="hudson.plugins.git.GitSCM" plugin="git@5.7.0">
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

TMPFILE="$(mktemp)"
echo "$CONFIG" > "$TMPFILE"

echo "[..] updating Jenkins job '${JOB_NAME}' ..."
docker cp "$TMPFILE" "petclinic-jenkins:/var/jenkins_home/jobs/${JOB_NAME}/config.xml"
rm -f "$TMPFILE"

echo "[ok] job configured — Pipeline from SCM"
echo "     repo:   ${REPO_URL}"
echo "     branch: ${BRANCH}"
echo "     script: Jenkinsfile"
echo
echo "Next: push Jenkinsfile + pom.xml to GitHub, then Build Now in Jenkins."
