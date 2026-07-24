#!/usr/bin/env bash
set -Eeuo pipefail

: "${SIGNOZ_GIT_REPO:=https://github.com/jamtools/signoz.git}"
: "${SIGNOZ_GIT_REF:=main}"
: "${SIGNOZ_COMPOSE_PATH:=deploy/docker/docker-compose.yaml}"
: "${SIGNOZ_WORKDIR:=/opt/signoz/repo}"
: "${SIGNOZ_START_MODE:=full}"
: "${SIGNOZ_INGEST_SERVICES:=zookeeper-1 clickhouse signoz-telemetrystore-migrator otel-collector}"
: "${SIGNOZ_IDLE_SHUTDOWN_ENABLED:=false}"
: "${SIGNOZ_IDLE_SHUTDOWN_SECONDS:=1200}"
: "${SIGNOZ_IDLE_CHECK_INTERVAL_SECONDS:=30}"
: "${SIGNOZ_MIN_UPTIME_BEFORE_IDLE_SECONDS:=300}"
: "${SIGNOZ_PROXY_METRICS_URL:=}"
: "${SIGNOZ_UI_ACTIVITY_FILE:=/opt/signoz/ui-active-at}"
: "${SIGNOZ_KEEP_DAEMON_AFTER_IDLE:=true}"
: "${DOCKER_HOST:=unix:///var/run/docker.sock}"

log() {
  printf '[signoz-dind] %s\n' "$*"
}

compose() {
  docker compose -f "$compose_file" "$@"
}

bool_true() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

metric_values_are_zero() {
  local pattern="$1"
  local require_found="${2:-false}"
  awk -v pattern="$pattern" -v require_found="$require_found" '
    $0 ~ pattern && $0 !~ /^#/ {
      found=1
      value=$NF + 0
      if (value != 0) {
        bad=1
      }
    }
    END {
      if (require_found == "true" && !found) {
        bad=1
      }
      exit bad
    }
  ' <<<"$metrics_body"
}

proxy_queues_empty() {
  if [[ -z "$SIGNOZ_PROXY_METRICS_URL" ]]; then
    log "idle shutdown blocked: SIGNOZ_PROXY_METRICS_URL is not configured"
    return 1
  fi

  if ! metrics_body="$(curl -fsS --max-time 5 "$SIGNOZ_PROXY_METRICS_URL")"; then
    log "idle shutdown blocked: failed to scrape proxy metrics from $SIGNOZ_PROXY_METRICS_URL"
    return 1
  fi

  if ! metric_values_are_zero '^otelcol_exporter_queue_size' true; then
    log "idle shutdown blocked: proxy exporter queue is not empty or metrics are absent"
    return 1
  fi

  if ! metric_values_are_zero '^otelcol_exporter_enqueue_failed'; then
    log "idle shutdown blocked: proxy enqueue failures are present"
    return 1
  fi

  if ! metric_values_are_zero '^otelcol_exporter_send_failed'; then
    log "idle shutdown blocked: proxy export failures are present"
    return 1
  fi

  return 0
}

ui_api_idle() {
  if [[ ! -e "$SIGNOZ_UI_ACTIVITY_FILE" ]]; then
    return 0
  fi

  local now activity_age
  now="$(date +%s)"
  activity_age=$((now - $(stat -c %Y "$SIGNOZ_UI_ACTIVITY_FILE")))
  if (( activity_age < SIGNOZ_IDLE_SHUTDOWN_SECONDS )); then
    log "idle shutdown blocked: UI/API activity marker is ${activity_age}s old"
    return 1
  fi

  return 0
}

maybe_idle_shutdown() {
  if ! bool_true "$SIGNOZ_IDLE_SHUTDOWN_ENABLED"; then
    return 0
  fi

  log "idle shutdown monitor enabled: idle=${SIGNOZ_IDLE_SHUTDOWN_SECONDS}s interval=${SIGNOZ_IDLE_CHECK_INTERVAL_SECONDS}s min_uptime=${SIGNOZ_MIN_UPTIME_BEFORE_IDLE_SECONDS}s"
  local started_at idle_since now uptime idle_for
  started_at="$(date +%s)"
  idle_since=""

  while kill -0 "$dockerd_pid" >/dev/null 2>&1; do
    sleep "$SIGNOZ_IDLE_CHECK_INTERVAL_SECONDS"
    now="$(date +%s)"
    uptime=$((now - started_at))

    if (( uptime < SIGNOZ_MIN_UPTIME_BEFORE_IDLE_SECONDS )); then
      log "idle shutdown blocked: uptime ${uptime}s below minimum"
      idle_since=""
      continue
    fi

    if proxy_queues_empty && ui_api_idle; then
      if [[ -z "$idle_since" ]]; then
        idle_since="$now"
        log "all safe-shutdown conditions hold; starting idle timer"
      fi
      idle_for=$((now - idle_since))
      if (( idle_for >= SIGNOZ_IDLE_SHUTDOWN_SECONDS )); then
        log "idle window elapsed; stopping SigNoz ${SIGNOZ_START_MODE} services"
        compose stop ${active_services:-} || true
        if bool_true "$SIGNOZ_KEEP_DAEMON_AFTER_IDLE"; then
          log "nested Docker daemon remains up for diagnostics or an external lifecycle controller"
          return 0
        fi
        kill "$dockerd_pid" >/dev/null 2>&1 || true
        return 0
      fi
      log "safe-shutdown conditions still hold for ${idle_for}s"
    else
      idle_since=""
    fi
  done
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


log "starting SigNoz compose stack from $compose_file"
cd "$(dirname "$compose_file")"
case "$SIGNOZ_START_MODE" in
  full)
    active_services=""
    compose up -d --remove-orphans
    ;;
  ingest-only)
    active_services="$SIGNOZ_INGEST_SERVICES"
    log "ingest-only mode starts services: $active_services"
    compose up -d --remove-orphans $active_services
    ;;
  *)
    log "unsupported SIGNOZ_START_MODE=$SIGNOZ_START_MODE; expected full or ingest-only"
    exit 1
    ;;
esac

log "SigNoz compose stack is starting"
compose ps
if [[ "$SIGNOZ_START_MODE" == "full" ]]; then
  log "UI should be available through the outer container port mapping, typically http://localhost:8080"
else
  log "ingest-only mode keeps UI/frontend services stopped unless an external lifecycle controller starts full mode"
fi

maybe_idle_shutdown
wait "$dockerd_pid"
