# Screenshot index

## CI pipeline

| File | What it shows |
|------|----------------|
| `01-docker-desktop-petclinic-devops-stack.png` | Docker Desktop — `petclinic-devops` compose stack running (Jenkins, SonarQube, Postgres) |
| `02-jenkins-build-02-empty-pipeline.png` | Jenkins Build #2 — empty pipeline (Start/End only, finished in ~41 ms) |
| `03-jenkins-build-05-unit-tests-passing.png` | Jenkins Build #5 — 61 tests, 59 passed, 2 skipped |
| `04-sonarqube-spring-petclinic-quality-gate.png` | SonarQube — `spring-petclinic` project dashboard, Quality Gate Passed |

Referenced from `DEVOPS.md` at repo root.

## Deployment demo (commit `cdef8ce`)

| File | What it shows |
|------|----------------|
| `09-deploy-app-results-welcome-screen.png` | Browser at `localhost:8080` — PetClinic welcome page after running the pipeline-setup-main.sh + 10-deploy-app.sh script |
| `commit-cdef8ce-deployed-version-difference.png` | GitHub diff for commit `cdef8ce` — `vets=Veterinarians` changed to `vets=Find Veterinarians` in `messages.properties` |
| `cdef8ce-jenkins-pipeline-trigger.png` | Jenkins console output — pipeline started by an SCM change and checking out commit `cdef8ce` |
| `pipeline-trigger-on-commit-cdef8ce.png` | Jenkins Build #18 status page — success, built from revision `cdef8ce` |
| `deployment-completed-on-jenkins.png` | Jenkins console output — Ansible deploy playbook run against `petclinic-prod`, ending in `[ok] deploy complete` |
| `production-vm-before-cdef8ce.png` | Production VM before deploy — nav bar still reads "VETERINARIANS" |
| `production-vm-after-cdef8ce.png` | Production VM after deploy — nav bar now reads "FIND VETERINARIANS", confirming the change shipped |

## Monitoring (Prometheus + Grafana)

| File | What it shows |
|------|----------------|
| `prometheus_installation.png` | Jenkins — Installed Plugins page showing the Prometheus metrics plugin enabled |
| `prometheus_running.png` | Prometheus — Status > Target health showing the `jenkins` scrape target `UP` |
| `prometheus_jenkins_metrics.png` | Prometheus — graph of `up{job="jenkins"}` confirming metrics are being scraped |
| `grafana_prometheus_connection.png` | Grafana — Prometheus data source config, "Successfully queried the Prometheus API" |
| `grafana_dashboard.png` | Grafana — "Jenkins: Performance and Health Overview" dashboard |

## Security scan

| File | What it shows |
|------|----------------|
| `petclinic_fork_zap.png` | OWASP ZAP scanning report for the deployed app — 0 high, 3 medium, 7 low risk alerts |
