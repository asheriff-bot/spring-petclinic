# Jenkins controller with the Docker CLI + Compose v2 plugin added.
#
# The base jenkins/jenkins image only ships the JVM; docker.sock is bind-mounted
# in so Testcontainers (which talks to the socket directly via the Docker Java
# client) works out of the box, but Spring Boot's docker-compose support shells
# out to the `docker` / `docker compose` binaries, which aren't present without
# this layer.
FROM jenkins/jenkins:lts-jdk17

USER root

COPY --from=docker:27-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker:27-cli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins

USER jenkins
