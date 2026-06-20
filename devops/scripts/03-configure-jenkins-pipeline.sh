#!/usr/bin/env bash
# Embed the full pipeline script in the Build job (avoids SCM reload / lightweight issues)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPO_URL="${REPO_URL:-https://github.com/asheriff-bot/spring-petclinic.git}"
BRANCH="${BRANCH:-main}"
JOB_NAME="${JOB_NAME:-Build}"

PIPELINE_SCRIPT=$(cat <<'GROOVY'
pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
    }

    environment {
        SONAR_HOST_URL = 'http://sonarqube:9000'
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/asheriff-bot/spring-petclinic.git'
            }
        }

        stage('Build & Test') {
            steps {
                sh './mvnw -B verify'
            }
        }

        stage('SonarQube Analysis') {
            steps {
                script {
                    try {
                        withCredentials([string(credentialsId: 'sonarqube-system-token', variable: 'SONAR_TOKEN')]) {
                            sh './mvnw -B sonar:sonar -DskipTests'
                        }
                    } catch (ignored) {
                        echo 'Skipping SonarQube: add Jenkins credential "sonarqube-system-token" (SonarQube user token).'
                    }
                }
            }
        }
    }

    post {
        always {
            junit allowEmptyResults: true, testResults: 'target/surefire-reports/*.xml'
        }
        success {
            echo 'Pipeline completed successfully.'
        }
        failure {
            echo 'Pipeline failed — see console output above.'
        }
    }
}
GROOVY
)

ESCAPED_SCRIPT=$(python3 -c 'import sys, xml.sax.saxutils as x; print(x.escape(sys.stdin.read()))' <<< "$PIPELINE_SCRIPT")

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
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps@4331.v9d06ed4658ff">
    <script>${ESCAPED_SCRIPT}</script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
EOF
)

TMPFILE="$(mktemp)"
echo "$CONFIG" > "$TMPFILE"

echo "[..] embedding pipeline in Jenkins job '${JOB_NAME}' ..."
docker cp "$TMPFILE" "petclinic-jenkins:/var/jenkins_home/jobs/${JOB_NAME}/config.xml"
rm -f "$TMPFILE"

echo "[..] restarting Jenkins to reload job definition ..."
docker restart petclinic-jenkins >/dev/null

echo "[..] waiting for Jenkins to come back ..."
for i in $(seq 1 30); do
  if curl -sf -o /dev/null http://localhost:8081/login; then
    echo "[ok] Jenkins is up — click Build Now (expect several minutes, not 0.1 sec)"
    exit 0
  fi
  sleep 3
done

echo "[warn] Jenkins may still be starting — open http://localhost:8081 and run Build Now"
exit 0
