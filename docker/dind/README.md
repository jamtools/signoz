# SigNoz Docker-in-Docker image

This image starts Docker-in-Docker, clones a SigNoz compose repository, and runs
its Docker Compose stack. It is intended for a dedicated privileged Hetzner host
that runs the platform/global SigNoz instance.

Default runtime behavior:

The default compose path follows current upstream SigNoz: `deploy/docker/docker-compose.yaml`.

- clone `https://github.com/jamtools/signoz.git`
- checkout `main`
- patch stale legacy `bitnami/zookeeper:3.7.1` only when that image appears in the selected compose file
- disable the upstream OpAMP manager override by default so the checked-in collector config exposes OTLP on `4317`/`4318`
- run `docker compose -f deploy/docker/docker-compose.yaml up -d --remove-orphans`

Example local run:

```bash
docker run --privileged --rm \
  -p 8080:8080 \
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
zookeeper-1 clickhouse signoz-telemetrystore-migrator otel-collector
```

Override `SIGNOZ_INGEST_SERVICES` if the compose file changes. Ingest-only mode
does not start the upstream `signoz` UI/API service unless it is listed. The
collector can drain to ClickHouse after ClickHouse and the telemetrystore migrator
are healthy, so UI/API startup remains optional for ingest-only wake.

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


## Collector OpAMP behavior

`SIGNOZ_DISABLE_OPAMP=true` is the DIND default. Current upstream compose starts
the collector with `--manager-config`/`--copy-path`, which lets the SigNoz OpAMP
server replace the file-based collector config. In a fresh DIND deployment that
default OpAMP config can start only health/pprof extensions, leaving OTLP `4317`
and `4318` closed even though Docker publishes them. The DIND image patches those
manager flags out by default so the repository `otel-collector-config.yaml` is
used directly and the OTLP receivers are available for executor readiness and
ingest smoke tests.

Set `SIGNOZ_DISABLE_OPAMP=false` only when you specifically want to validate the
upstream OpAMP-managed collector behavior.
