# jamtools/signoz fork journal

This file records the intentional delta between `jamtools/signoz` and upstream
`signoz/signoz` before updating the fork to current upstream. Keep it in the fork
until every important change has either been preserved, replaced by upstream, or
explicitly dropped.

Last audited on: 2026-06-17

Audited branch: `vk/signoz-ghcr-image`
Upstream update branch: `vk/signoz-upstream-dind`
Audited head: `5c05f0e3439d564b9ebea1a84ae4cf61c0c59a49`
Upstream reference: `upstream/main` at `03796f012ff5bc3ae5d1b7954a09dc4477e668a4`
Ahead/behind at audit time: 20 commits ahead, 2809 commits behind.

## High-level fork delta

The fork is not a small patch on current upstream. It is an older SigNoz Docker
layout with local operational changes plus new DIND/GHCR packaging. Important
high-level differences:

1. The old upstream `deploy/docker/clickhouse-setup/*` Docker assets were moved
   to the repository root.
2. The fork relies on root-level `docker-compose.yaml` and root-level collector
   config files.
3. Current upstream no longer has root `docker-compose.yaml`; upstream now uses
   `deploy/docker/docker-compose.yaml` with different service names and a newer
   single `signoz` service.
4. The fork has local log-ingest customizations for fluentforward, Docker logs,
   and excluding SigNoz/Coolify containers from self-ingestion.
5. The fork has nginx DNS cache behavior changes.
6. The fork adds our new GHCR-published Docker-in-Docker image and lifecycle
   entrypoint for full vs ingest-only SigNoz startup.

## Fork-only commits

| Commit | Summary | Files touched | Preserve decision |
| --- | --- | --- | --- |
| `7808a6cec` | Remove hotrod app from docker-compose.yaml (#1) | `docker-compose.yaml` after layout move | Replace/drop. Upstream's current compose no longer uses this old hotrod layout in the same way; verify no demo app is started in current upstream. |
| `bb35411cc` | Move docker files to root dir (#2) | Moves many files from `deploy/docker/clickhouse-setup/*` to repo root, including compose files, ClickHouse config, collector config, data dirs, scripts. | Drop as-is. Current upstream uses `deploy/docker/docker-compose.yaml`; DIND should adapt to upstream path rather than preserving root relocation unless we intentionally want a flattened distribution. |
| `301971050` | comment out hostfs volume (#3) | `docker-compose.yaml` | Re-evaluate. Current upstream collector still mounts host paths differently. Preserve the intent only if hostfs causes local/DIND breakage. |
| `a6d48730c` | change restart policy to no | `docker-compose.yaml` | Re-evaluate. Likely old workaround for migration/init containers. Current upstream has explicit migrator/init services; preserve only if needed for DIND idempotence. |
| `f78bcd4e3` | add restart no for migrator | `docker-compose.yaml` | Preserve intent, not patch. Migrator/init containers should not restart forever; verify current upstream already handles this. |
| `53ce24695` | fix hostfs for otel-collector | `docker-compose.yaml` | Re-evaluate alongside `301971050`. Preserve only if collector needs host proc/sys paths under DIND. |
| `2c6eabd1f` | change nginx conf to invalidate its dns cache | `deploy/docker/common/nginx-config.conf` | Preserve intent if current upstream frontend still proxies by Docker DNS name. The fork added `resolver 127.0.0.11 valid=10s;` to reduce stale query-service DNS in Docker. Current upstream has changed service model, so adapt only if still relevant. |
| `348e83df0` | enable fluentforward logs | `docker-compose.yaml`, `otel-collector-config.yaml` | Preserve if we still require Fluent Forward on `24224`. This matters for our cold ingest and log shipping experiments. Current upstream collector config must be checked for fluentforward support. |
| `be4f3a69e` | remove unrelated otel collector config, trying to exclude SigNoz docker container logs | `otel-collector-config.yaml` | Preserve intent, not necessarily exact config. We want to avoid self-ingesting noisy SigNoz/Coolify container logs. Rebuild against current upstream collector syntax. |
| `b49878273` | revert to see if fluent logs work again | `otel-collector-config.yaml` | Historical debugging. Do not preserve as a standalone change; preserve final intent only. |
| `273c2aa92` | enable http logging | `otel-collector-config.yaml` | Dropped later by `c7086a698`. Do not preserve. |
| `df996d087` | exclude signoz containers from docker logs | `otel-collector-config.yaml` | Preserve intent: exclude SigNoz's own containers from Docker log ingestion to avoid feedback loops/noise. |
| `1403d7ec9` | exclude coolify logs | `otel-collector-config.yaml` | Preserve intent if this SigNoz instance will observe hosts that also run Coolify. For dedicated SigNoz hosts this may be irrelevant; for shared hosts keep. |
| `c7d967172` | remove ^ | `otel-collector-config.yaml` | Historical regex tuning. Do not preserve as a standalone change; preserve final regex behavior only. |
| `dace3c621` | put ^signoz back in | `otel-collector-config.yaml` | Historical regex tuning. Do not preserve as a standalone change; preserve final regex behavior only. |
| `c7086a698` | remove http logging | `otel-collector-config.yaml` | Preserve final state: HTTP logging should remain disabled unless explicitly needed for debugging. |
| `d0a59faeb` | exclude signoz containers again | `otel-collector-config.yaml` | Preserve final intent with `df996d087`. |
| `32a8ea248` | exclude coolify from logs | `otel-collector-config.yaml` | Preserve final intent with `1403d7ec9` if Coolify is on observed hosts. |
| `341d29879` | Add GHCR SigNoz DIND image workflow | `.github/workflows/ghcr-signoz-dind.yml`, `docker/dind/*` | Preserve. This is our image publishing path for `ghcr.io/mickmister/signoz-dind`. |
| `5c05f0e34` | Add SigNoz ingest-only DIND lifecycle mode | `docker/dind/*` | Preserve and adapt. This is our full/ingest-only lifecycle, idle shutdown guard, service selection, and DIND runtime behavior. Must be updated for current upstream compose names/path. |

## Final file-level delta at audit time

### Added by our fork

- `.github/workflows/ghcr-signoz-dind.yml`
  - Publishes the DIND image to GHCR using Buildx/QEMU.
  - Tags include SHA, branch, and `latest` on `main`.
- `docker/dind/Dockerfile`
  - Builds from `docker:28.5.2-dind`.
  - Installs bash/git/curl/ca-certificates.
  - Sets defaults for `SIGNOZ_GIT_REPO`, `SIGNOZ_GIT_REF`, `SIGNOZ_COMPOSE_PATH`, `SIGNOZ_WORKDIR`, startup mode, idle shutdown, and DIND Docker socket.
- `docker/dind/entrypoint.sh`
  - Starts nested Docker.
  - Clones or updates the configured SigNoz repo/ref.
  - Patches stale `bitnami/zookeeper:3.7.1` to `zookeeper:3.7.2` in the old compose layout.
  - Starts either full compose or the ingest-only service list.
  - Supports safe idle shutdown by scraping collector proxy metrics and checking queue/failure/UI-idle conditions.
- `docker/dind/README.md`
  - Documents full vs ingest-only modes and safe idle shutdown.

### Moved/flattened from old upstream layout

The fork moved these old files from `deploy/docker/clickhouse-setup/` to the
repository root:

- `docker-compose.yaml`
- `docker-compose-core.yaml`
- `docker-compose-local.yaml`
- `docker-compose.testing.yaml`
- `alertmanager.yml`
- `alerts.yml`
- `clickhouse-cluster.xml`
- `clickhouse-config.xml`
- `clickhouse-storage.xml`
- `clickhouse-users.xml`
- `custom-function.xml`
- `keeper_config.xml`
- `otel-collector-config.yaml`
- `otel-collector-opamp-config.yaml`
- `prometheus.yml`
- `data/**/.gitkeep`
- `user_scripts/histogramQuantile`
- `user_scripts/histogramQuantile.go`

Current upstream does not use this root layout. Treat this as an old convenience
layout and avoid carrying it forward unless explicitly needed.

### Root `docker-compose.yaml` behavior to preserve or reconsider

The fork's root compose currently includes these notable behaviors:

- SigNoz frontend is exposed on `3301`.
- OTLP gRPC is exposed on `4317`.
- OTLP HTTP is exposed on `4318`.
- Fluent Forward logs are exposed on `24224`.
- ClickHouse is exposed on `9000` and `8123` in the inner compose.
- `otel-collector-migrator` has `restart: no`.
- `otel-collector` mounts `/proc:/hostfs/proc:ro` and `/sys:/hostfs/sys:ro`.
- `logspout` forwards Docker logs to `otel-collector:2255`.

When moving to upstream's current `deploy/docker/docker-compose.yaml`, map these
behaviors carefully because upstream service names and ports changed.

### `otel-collector-config.yaml` behavior to preserve or reconsider

Final fork state includes:

- `fluentforward` receiver.
- `tcplog/docker` receiver.
- log filter named `signoz_logs_filter` with expression excluding containers that match:
  - `logspout`
  - `frontend`
  - `alertmanager`
  - `query-service`
  - `otel-collector`
  - `clickhouse`
  - `zookeeper`
  - `coolify`
- OTLP receiver supports gRPC and HTTP.
- Jaeger receiver remains enabled.
- Logs pipeline receives from `otlp`, `tcplog/docker`, and `fluentforward`.
- HTTP logging debugging was removed in the final state.

Preservation target: avoid self-ingesting SigNoz logs, avoid Coolify noise where
relevant, and keep Fluent Forward support if the executor/customer stacks need
it.

### `deploy/docker/common/nginx-config.conf` behavior to preserve or reconsider

The fork adds:

```nginx
resolver 127.0.0.11 valid=10s;
```

Intent: reduce stale Docker DNS cache issues when nginx proxies to another
container by service name.

Current upstream has a newer single `signoz` service and may not need the same
frontend/query-service proxy pattern. Preserve only if upstream's nginx still
resolves dynamic Docker service names.

## Current upstream compose differences that affect migration

At upstream/main `03796f012`, the Docker compose path is:

```text
deploy/docker/docker-compose.yaml
```

There is no root `docker-compose.yaml` in upstream/main.

Current upstream services are:

```text
init-clickhouse
zookeeper-1
clickhouse
signoz
otel-collector
signoz-telemetrystore-migrator
```

This differs from the fork's old assumptions:

```text
zookeeper-1
clickhouse
otel-collector-migrator
query-service
otel-collector
frontend
alertmanager
logspout
```

Migration implications:

- `SIGNOZ_COMPOSE_PATH` should probably default to `deploy/docker/docker-compose.yaml` after upstream update.
- `SIGNOZ_INGEST_SERVICES` must be rebuilt for current upstream. Likely candidates are `zookeeper-1`, `clickhouse`, `signoz-telemetrystore-migrator`, `signoz`, and `otel-collector`, but this must be tested.
- UI port should likely move from fork-local `3301` to upstream `8080`, unless we intentionally preserve the old frontend/nginx port externally.
- The old `bitnami/zookeeper:3.7.1` patch may be obsolete because current upstream uses `signoz/zookeeper:3.7.1`.
- The old `query-service`/`frontend` split no longer maps directly to upstream's current `signoz` service.

## Proposed carry-forward matrix

| Area | Carry forward? | Notes |
| --- | --- | --- |
| GHCR DIND workflow | Yes | Required for Hetzner deployment using our image. |
| DIND Dockerfile | Yes, adapt | Compose path/default ports/service names must change for current upstream. |
| DIND full mode | Yes, adapt | Should run current upstream compose full stack. |
| DIND ingest-only mode | Yes, adapt/test | Rebuild service list for current upstream. |
| DIND idle shutdown guard | Yes | Independent of upstream compose, but service stop behavior must use new service names. |
| Root compose relocation | Probably no | Prefer upstream layout to reduce drift. |
| Remove hotrod | Probably no | Upstream layout likely already changed. Verify. |
| Migrator restart policy | Preserve intent | Ensure migrators/init jobs do not restart forever. |
| Hostfs changes | Re-evaluate | DIND may not need hostfs; host metrics may differ. |
| Fluent Forward receiver | Probably yes | Needed if customer/executor log shipping uses Fluent Forward. |
| Docker log exclusions | Yes, adapt | Avoid self-ingestion loops/noise. Update container names to upstream (`signoz`, `signoz-otel-collector`, etc.). |
| Coolify log exclusion | Conditional | Keep if SigNoz observes hosts running Coolify; otherwise omit for dedicated hosts. |
| HTTP logging debug changes | No | Final fork removed this. |
| nginx Docker resolver | Conditional | Preserve only if upstream nginx still proxies by dynamic service name. |

## Recommended upstream update strategy

Do not merge the old fork branch wholesale into upstream/main. Instead:

1. Create a new branch from `upstream/main`.
2. Add this journal first so the audit survives the update work.
3. Re-apply the GHCR DIND workflow and DIND image files.
4. Adapt DIND defaults to upstream's current compose path/services.
5. Rebuild log filtering/fluentforward behavior against current upstream collector config.
6. Drop the old root compose relocation unless testing proves it is still needed.
7. Validate full mode and ingest-only mode before replacing the deploy image reference.
