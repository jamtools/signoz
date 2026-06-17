#!/usr/bin/env bash
set -Eeuo pipefail

: "${SIGNOZ_GIT_REPO:=https://github.com/jamtools/signoz.git}"
: "${SIGNOZ_GIT_REF:=main}"
: "${SIGNOZ_COMPOSE_PATH:=docker-compose.yaml}"
: "${SIGNOZ_WORKDIR:=/opt/signoz/repo}"
: "${SIGNOZ_ZOOKEEPER_IMAGE:=zookeeper:3.7.2}"
: "${DOCKER_HOST:=unix:///var/run/docker.sock}"

log() {
  printf '[signoz-dind] %s\n' "$*"
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [[ -n "${dockerd_pid:-}" ]] && kill -0 "$dockerd_pid" >/dev/null 2>&1; then
    log "stopping nested SigNoz compose stack"
    if [[ -f "${compose_file:-}" ]]; then
      (cd "$(dirname "$compose_file")" && docker compose -f "$compose_file" down --remove-orphans) || true
    fi
    log "stopping nested Docker daemon"
    kill "$dockerd_pid" >/dev/null 2>&1 || true
    wait "$dockerd_pid" >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

log "starting nested Docker daemon"
dockerd-entrypoint.sh dockerd "$@" &
dockerd_pid=$!

log "waiting for nested Docker daemon"
for attempt in $(seq 1 60); do
  if docker info >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$dockerd_pid" >/dev/null 2>&1; then
    log "nested Docker daemon exited before it became ready"
    wait "$dockerd_pid"
  fi
  if [[ "$attempt" == "60" ]]; then
    log "timed out waiting for nested Docker daemon"
    exit 1
  fi
  sleep 1
done

if [[ ! -d "$SIGNOZ_WORKDIR/.git" ]]; then
  log "cloning $SIGNOZ_GIT_REPO into $SIGNOZ_WORKDIR"
  rm -rf "$SIGNOZ_WORKDIR"
  git clone "$SIGNOZ_GIT_REPO" "$SIGNOZ_WORKDIR"
fi

log "checking out SigNoz ref $SIGNOZ_GIT_REF"
cd "$SIGNOZ_WORKDIR"
git fetch --tags origin
git checkout "$SIGNOZ_GIT_REF"
git reset --hard "$SIGNOZ_GIT_REF"
if [[ "$SIGNOZ_GIT_REF" == "main" ]]; then
  git pull --ff-only origin main
fi

compose_file="$SIGNOZ_WORKDIR/$SIGNOZ_COMPOSE_PATH"
if [[ ! -f "$compose_file" ]]; then
  log "compose file not found: $compose_file"
  exit 1
fi

if grep -q 'bitnami/zookeeper:3.7.1' "$compose_file"; then
  log "patching stale upstream zookeeper image to $SIGNOZ_ZOOKEEPER_IMAGE"
  sed -i "s#bitnami/zookeeper:3.7.1#$SIGNOZ_ZOOKEEPER_IMAGE#g" "$compose_file"
fi

log "starting SigNoz compose stack from $compose_file"
cd "$(dirname "$compose_file")"
docker compose -f "$compose_file" up -d --remove-orphans

log "SigNoz compose stack is starting"
docker compose -f "$compose_file" ps
log "UI should be available through the outer container port mapping, typically http://localhost:3301"

wait "$dockerd_pid"
