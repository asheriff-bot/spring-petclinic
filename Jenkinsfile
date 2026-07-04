pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
    }

    environment {
        SONAR_HOST_URL = 'http://sonarqube:9000'
        // Jenkins runs as a container with the host's docker.sock mounted, so
        // Testcontainers-spawned containers (and Ryuk) are siblings, not children,
        // of Jenkins. Testcontainers' auto-detected docker host (172.17.0.1, the
        // default bridge gateway) isn't reachable from Jenkins' custom bridge
        // network (petclinic-devops-net), causing Ryuk connection failures.
        // Override with the Docker Desktop host alias, reachable from any network.
        TESTCONTAINERS_HOST_OVERRIDE = 'host.docker.internal'
        // Same problem, different subsystem: Spring Boot's docker-compose support
        // (used by PostgresIntegrationTests) resolves the readiness-check host from
        // DOCKER_HOST/docker context, which falls back to 127.0.0.1 for a unix://
        // socket — that's Jenkins itself, not the host publishing the compose
        // service's port. SERVICES_HOST overrides that resolution explicitly.
        SERVICES_HOST = 'host.docker.internal'
    }

    triggers {
        pollSCM('* * * * *')  // Poll every minute
    }

    stages {
        stage('Checkout') {
            steps {
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: '*/asanche4/deploy-pipeline']],
                    userRemoteConfigs: [[url: 'https://github.com/asheriff-bot/spring-petclinic.git']]
                ])
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
                        withSonarQubeEnv(credentialsId: 'sonarqube-system-token', installationName: 'SonarQube') {
                            sh './mvnw -B sonar:sonar -DskipTests'
                        }
                    } catch (Exception err) {
                        // Log the error to the console
                        echo "Caught an error: ${err.getMessage()}"
                        echo 'Skipping SonarQube scan — install plugin via devops/scripts/05-configure-sonarqube-jenkins.sh'
                        echo 'and ensure credential sonarqube-system-token exists under System → Global.'
                    }
                }
            }
        }

        stage('Quality Gate') {
            steps {
                script {
                    try {
                        timeout(time: 5, unit: 'MINUTES') {
                            waitForQualityGate abortPipeline: true
                        }
                    } catch (err) {
                        if (err.message?.contains('Quality Gate')) {
                            error("Quality Gate failed: ${err.message}")
                        }
                        echo "Skipping Quality Gate: ${err.message}"
                    }
                }
            }
        }

        stage('ZAP Baseline Scan') {
            steps {
                sh './devops/scripts/06-run-zap-baseline.sh'
            }
        }

        stage('Deploy') {
            steps {
                sh './devops/scripts/09-deploy-app.sh'
            }
        }
    }

    post {
        always {
            junit allowEmptyResults: true, testResults: 'target/surefire-reports/*.xml'
            archiveArtifacts artifacts: 'devops/reports/zap/*.html', allowEmptyArchive: true
        }
        success {
            echo 'Pipeline completed successfully.'
        }
        failure {
            echo 'Pipeline failed — see console output above.'
        }
    }
}
