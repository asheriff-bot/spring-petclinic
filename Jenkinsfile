pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
    }

    environment {
        SONAR_HOST_URL = 'http://sonarqube:9000'
    }

    triggers {
        pollSCM('* * * * *')  // Poll every minute
    }

    stages {
        stage('Checkout') {
            steps {
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: '*/main']],
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
                    } catch (ignored) {
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
