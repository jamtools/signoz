# Runs a SigNoz Docker Compose checkout inside Docker-in-Docker.
# The container is intended for a dedicated, privileged platform SigNoz host.
FROM docker:28.5.2-dind

RUN apk add --no-cache bash git ca-certificates curl

COPY docker/dind/entrypoint.sh /usr/local/bin/signoz-dind-entrypoint.sh
RUN chmod 0755 /usr/local/bin/signoz-dind-entrypoint.sh

ENV SIGNOZ_GIT_REPO=https://github.com/jamtools/signoz.git \
    SIGNOZ_GIT_REF=main \
    SIGNOZ_COMPOSE_PATH=deploy/docker/docker-compose.yaml \
    SIGNOZ_WORKDIR=/opt/signoz/repo \
    SIGNOZ_ZOOKEEPER_IMAGE=zookeeper:3.7.2 \
    SIGNOZ_START_MODE=full \
    SIGNOZ_INGEST_SERVICES="zookeeper-1 clickhouse signoz-telemetrystore-migrator otel-collector" \
    SIGNOZ_DISABLE_OPAMP=true \
    SIGNOZ_IDLE_SHUTDOWN_ENABLED=false \
    SIGNOZ_IDLE_SHUTDOWN_SECONDS=1200 \
    SIGNOZ_IDLE_CHECK_INTERVAL_SECONDS=30 \
    SIGNOZ_MIN_UPTIME_BEFORE_IDLE_SECONDS=300 \
    SIGNOZ_PROXY_METRICS_URL= \
    SIGNOZ_UI_ACTIVITY_FILE=/opt/signoz/ui-active-at \
    SIGNOZ_KEEP_DAEMON_AFTER_IDLE=true \
    DOCKER_TLS_CERTDIR= \
    DOCKER_HOST=unix:///var/run/docker.sock

VOLUME ["/var/lib/docker", "/opt/signoz"]

EXPOSE 8080 4317 4318 2181 8123 9000

ENTRYPOINT ["/usr/local/bin/signoz-dind-entrypoint.sh"]
