# Commands run during manual setup (2026-06-20)
# kept for audit / reproducibility

# --- fork & clone (done earlier) ---
# gh repo fork spring-projects/spring-petclinic --clone=false
# git clone https://github.com/asheriff-bot/spring-petclinic.git

# --- network ---
docker network create \
  --driver bridge \
  --label project=spring-petclinic \
  --label env=mini5-devops \
  petclinic-devops-net

# --- stack ---
cd devops
docker compose pull
docker compose up -d
docker compose ps
docker network inspect petclinic-devops-net

# --- sanity checks ---
curl -I http://localhost:8081/login
curl http://localhost:9000/api/system/status

# Jenkins initial password (run locally, do not commit output):
# docker exec petclinic-jenkins cat /var/jenkins_home/secrets/initialAdminPassword

# --- stop stack ---
# ./devops/scripts/03-stop-stack.sh
# ./devops/scripts/03-stop-stack.sh -v

# --- jenkins pipeline + quality gate ---
# ./devops/scripts/05-configure-sonarqube-jenkins.sh
# ./devops/scripts/04-configure-jenkins-pipeline.sh
