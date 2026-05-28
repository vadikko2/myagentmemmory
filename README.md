# myagentmemmory

Deploy artifacts for [agentmemory](https://github.com/rohitg00/agentmemory) on **Timeweb Cloud Apps** — persistent `/data`, HMAC auth for Cursor MCP, and optional backups to **Timeweb S3**.

## Quick start

| Step | Doc |
|------|-----|
| Deploy to Timeweb Apps | [docs/TIMEWEB_DEPLOY.md](docs/TIMEWEB_DEPLOY.md) |
| Connect Cursor | [docs/CURSOR_CONFIG.md](docs/CURSOR_CONFIG.md) |
| Regenerate files with an AI agent | [docs/DEPLOY_AGENT_PROMPT.md](docs/DEPLOY_AGENT_PROMPT.md) |

## Deploy on Timeweb Apps (Docker Compose)

Use root **`docker-compose.yml`** (Git deploy). It has **no `volumes:`** and **no `ports:`** — both break Timeweb routing. Set Storage **`/data`** and container port **8080** in the panel.

Set **container port 80** in the panel (not 8080). Health: **`/agentmemory/livez`**. See [docs/TIMEWEB_DEPLOY.md](docs/TIMEWEB_DEPLOY.md).

## Local smoke test

```bash
docker compose -f docker-compose.yml -f docker-compose.local.yml up --build
curl -sf http://localhost:8080/agentmemory/livez
```

Copy `AGENTMEMORY_SECRET=...` from container logs on first boot.

## Layout

```
deploy/timeweb/   Dockerfile, entrypoint.sh, backup.sh
docker-compose.yml        Timeweb Apps (no volumes)
docker-compose.local.yml  local bind mount .data:/data
docs/             deployment and Cursor guides
```

## Timeweb Apps settings

- **Port:** 80 (Timeweb) / 3111 (local direct mode)  
- **Health:** `/agentmemory/livez`  
- **Volume:** `/data`  
- **S3 endpoint:** `https://s3.twcstorage.ru` (region `ru-1`)
