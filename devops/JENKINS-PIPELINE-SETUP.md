# Jenkins Pipeline Setup — spring-petclinic

## 1. Push pipeline files to your fork

```bash
cd spring-petclinic
git add Jenkinsfile pom.xml devops/
git commit -m "Add Jenkins CI pipeline and SonarQube Maven config"
git push origin main
```

## 2. SonarQube token

1. Open http://localhost:9000 and sign in (`admin` / your password).
2. **My Account → Security → Generate Token** (name: `jenkins`).
3. Copy the token.

## 3. Jenkins credential

1. http://localhost:8081 → **Manage Jenkins → Credentials**.
2. **(global) → Add Credentials**.
3. Kind: **Secret text**, ID: **`sonarqube-token`**, Secret: paste SonarQube token.

## 4. Configure the Build job

From repo root:

```bash
./devops/scripts/03-configure-jenkins-pipeline.sh
```

This switches the **Build** job to **Pipeline from SCM** using `Jenkinsfile` on `main`.

## 5. Run the pipeline

1. Jenkins dashboard → **Build** → **Build Now**.
2. Open **Console Output** — expect checkout, Maven verify (~2–5 min), SonarQube scan.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Checkout fails | Push `Jenkinsfile` to GitHub first |
| SonarQube skipped | Add credential `sonarqube-token` |
| SonarQube connection refused | Ensure stack is up: `./devops/scripts/02-start-stack.sh` |
| Build &lt; 1 second | Old empty pipeline — re-run step 4 |
