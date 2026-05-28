# myagentmemmory

Deploy artifacts for [agentmemory](https://github.com/rohitg00/agentmemory) on **Timeweb Cloud Apps** — persistent `/data`, HMAC auth for Cursor MCP, and optional backups to **Timeweb S3**.

## Quick start

| Step | Doc |
|------|-----|
| Deploy to Timeweb Apps | [docs/TIMEWEB_DEPLOY.md](docs/TIMEWEB_DEPLOY.md) |
| Connect Cursor | [docs/CURSOR_CONFIG.md](docs/CURSOR_CONFIG.md) |
| Regenerate files with an AI agent | [docs/DEPLOY_AGENT_PROMPT.md](docs/DEPLOY_AGENT_PROMPT.md) |

## Local smoke test

```bash
docker compose up --build
curl -sf http://localhost:3111/agentmemory/livez
```

Copy `AGENTMEMORY_SECRET=...` from container logs on first boot.

## Layout

```
deploy/timeweb/   Dockerfile, entrypoint.sh, backup.sh
docker-compose.yml   local dev only
docs/             deployment and Cursor guides
```

## Timeweb Apps settings

- **Port:** 3111  
- **Health:** `/agentmemory/livez`  
- **Volume:** `/data`  
- **S3 endpoint:** `https://s3.twcstorage.ru` (region `ru-1`)
