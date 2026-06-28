# Jenkins Pipeline Setup — spring-petclinic

## 1. Push pipeline files to your fork

```bash
cd spring-petclinic
git add Jenkinsfile pom.xml devops/
git commit -m "Add Jenkins CI pipeline and SonarQube Maven config"
git push origin main
```

## 2. Wire SonarQube into Jenkins (auto-provisioned)

From repo root:

```bash
./devops/scripts/05-configure-sonarqube-jenkins.sh
./devops/scripts/04-configure-jenkins-pipeline.sh
```

`05` does everything that used to be manual:

- installs the SonarQube Jenkins plugin
- generates a SonarQube user token via the SonarQube REST API
- injects it into Jenkins as the `sonarqube-system-token` Secret-text credential
- registers the SonarQube server in Jenkins global config

`04` switches the **Build** job to **Pipeline from SCM** using `Jenkinsfile` on `main`.

### Bring your own token

If you already have a SonarQube token (or your admin password is not the default `admin`), set env vars before running `05`:

```bash
SONAR_TOKEN=squ_xxx ./devops/scripts/05-configure-sonarqube-jenkins.sh
# or
SONAR_ADMIN_PASSWORD='your-pw' ./devops/scripts/05-configure-sonarqube-jenkins.sh
```

Other overrides: `SONAR_NAME`, `SONAR_URL` (as Jenkins sees it), `SONAR_PUBLIC_URL` (host-side, used for REST calls), `SONAR_TOKEN_NAME`, `CREDENTIAL_ID`, `JENKINS_CONTAINER`.

## 3. Run the pipeline

1. Jenkins dashboard → **Build** → **Build Now**.
2. Open **Console Output** — expect checkout, Maven verify (~2–5 min), SonarQube scan, Quality Gate.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Checkout fails | Push `Jenkinsfile` to GitHub first |
| `05` aborts on SonarQube login | Set `SONAR_ADMIN_PASSWORD` env var |
| Credential not found in Jenkins | `docker logs petclinic-jenkins \| grep '\[init\]'` — the Groovy init script logs success/failure |
| SonarQube connection refused | Ensure stack is up: `./devops/scripts/02-start-stack.sh` |
| Build < 1 second | Old empty pipeline — re-run `./devops/scripts/04-configure-jenkins-pipeline.sh` |
| Quality Gate skipped | Re-run `./devops/scripts/05-configure-sonarqube-jenkins.sh` |
