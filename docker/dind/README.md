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
