# DevOps Stack Setup Log

> CMU MINI-5 DevOps Mini-project — manual setup notes  
> Engineer: akram_personal  
> Date: 2026-06-20

---

## Task 1 — Fork & clone spring-petclinic

**Upstream:** https://github.com/spring-projects/spring-petclinic

1. Opened GitHub → forked `spring-projects/spring-petclinic` to my account.
2. Fork URL: https://github.com/asheriff-bot/spring-petclinic
3. Cloned locally:

```bash
cd "/Users/akram_personal/Desktop/2025/GRAD_2024_APPLCN's/CMU/MINI-5/DEVOPS/Mini-project"
git clone https://github.com/asheriff-bot/spring-petclinic.git
cd spring-petclinic
git remote -v
# origin  https://github.com/asheriff-bot/spring-petclinic.git (fetch)
# origin  https://github.com/asheriff-bot/spring-petclinic.git (push)
```

Verified fork parent with `gh`:

```bash
gh repo view asheriff-bot/spring-petclinic --json isFork,parent,url
# isFork: true, parent: spring-projects/spring-petclinic
```

---

## Task 2 — Custom Docker network

Created a dedicated bridge network so Jenkins and SonarQube can resolve each other by container name (and so we can attach the app DB stack later if needed).

```bash
docker network create \
  --driver bridge \
  --label project=spring-petclinic \
  --label env=mini5-devops \
  petclinic-devops-net
```

Or use the helper script:

```bash
chmod +x devops/scripts/01-create-network.sh
./devops/scripts/01-create-network.sh
```

---

## Task 3 — Jenkins container (on custom network)

Base image: `jenkins/jenkins:lts-jdk17`

- Host port **8081** → container 8080 (8080 reserved for petclinic app)
- Agent port **50000**
- Volume `jenkins_home` for persistent config/jobs
- Docker socket mounted for future pipeline builds

Defined in `devops/docker-compose.yml` service `jenkins`.

---

## Task 4 — SonarQube container (on custom network)

Base images:
- `sonarqube:lts-community`
- `postgres:15-alpine` (SonarQube DB — required for LTS)

- Host port **9000**
- JDBC URL inside network: `jdbc:postgresql://sonarqube-db:5432/sonarqube`

Defined in `devops/docker-compose.yml` services `sonarqube` + `sonarqube-db`.

---

## Start the stack

```bash
chmod +x devops/scripts/*.sh
./devops/scripts/02-start-stack.sh
```

Check status:

```bash
docker compose -f devops/docker-compose.yml ps
docker network inspect petclinic-devops-net
```

Get initial Jenkins admin password:

```bash
docker exec petclinic-jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

---

## Endpoints

| Service   | URL                      | Notes                          |
|-----------|--------------------------|--------------------------------|
| Jenkins   | http://localhost:8081    | Complete setup wizard on first |
| SonarQube | http://localhost:9000    | Default admin/admin (change)   |

---

## Stop / clean up

```bash
cd devops && docker compose down          # keep volumes
cd devops && docker compose down -v       # remove volumes too
docker network rm petclinic-devops-net    # only after containers removed
```
