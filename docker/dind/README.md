# SigNoz Docker-in-Docker image

This image starts Docker-in-Docker, clones a SigNoz compose repository, and runs
its Docker Compose stack. It is intended for a dedicated privileged Hetzner host
that runs the platform/global SigNoz instance.

Default runtime behavior:

- clone `https://github.com/jamtools/signoz.git`
- checkout `main`
- patch stale `bitnami/zookeeper:3.7.1` to `${SIGNOZ_ZOOKEEPER_IMAGE:-zookeeper:3.7.2}`
- run `docker compose -f docker-compose.yaml up -d --remove-orphans`

Example local run:

```bash
docker run --privileged --rm \
  -p 3301:3301 \
  -p 4317:4317 \
  -p 4318:4318 \
  -v signoz-dind-docker:/var/lib/docker \
  -v signoz-dind-repo:/opt/signoz \
  ghcr.io/mickmister/signoz-dind:latest
```

The image is generic: override `SIGNOZ_GIT_REPO`, `SIGNOZ_GIT_REF`, and
`SIGNOZ_COMPOSE_PATH` to test a fork, branch, or upstream checkout.


## Startup modes

`SIGNOZ_START_MODE=full` is the default and starts the whole compose stack,
including the frontend. Use this for the platform/global SigNoz host because it
should remain always on and must not depend on cold-start behavior.

`SIGNOZ_START_MODE=ingest-only` starts only the backend services needed to drain
queued telemetry by default:

```text
zookeeper-1 clickhouse otel-collector-migrator query-service otel-collector
```

Override `SIGNOZ_INGEST_SERVICES` if the compose file changes. Ingest-only mode
does not start the frontend, alertmanager, or logspout unless they are listed.
The query service remains part of the backend dependency chain because the
collector waits for it in the current compose file, but it is not published by
the outer container unless the host maps its port.

## Safe idle shutdown guard

Set `SIGNOZ_IDLE_SHUTDOWN_ENABLED=true` to let the entrypoint stop the active
compose services after all safe-shutdown conditions hold for
`SIGNOZ_IDLE_SHUTDOWN_SECONDS` seconds. The guard requires:

- `SIGNOZ_PROXY_METRICS_URL` is configured and scrapeable;
- proxy exporter queue metrics report zero queued items;
- proxy enqueue/export failure metrics are zero when present;
- `SIGNOZ_UI_ACTIVITY_FILE` is absent or older than the idle window;
- `SIGNOZ_MIN_UPTIME_BEFORE_IDLE_SECONDS` has elapsed.

After idle shutdown, the nested Docker daemon remains running by default
(`SIGNOZ_KEEP_DAEMON_AFTER_IDLE=true`) so an external lifecycle controller can
inspect or restart services without losing diagnostics. Set it to `false` only
when the outer container restart policy will not immediately recreate a stopped
backend.
