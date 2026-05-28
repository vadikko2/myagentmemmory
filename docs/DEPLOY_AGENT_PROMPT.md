# Промпт для агента: артефакты деплоя agentmemory (Timeweb)

Скопируйте блок ниже в Cursor / Claude Code, чтобы сгенерировать или обновить файлы в репозитории.

---

## Задача

Сгенерируй или обнови все файлы для развёртывания [agentmemory](https://github.com/rohitg00/agentmemory) в **Timeweb Cloud Apps** с подключением **Cursor** через MCP и бэкапами в **Timeweb S3** (`https://s3.twcstorage.ru`, region `ru-1`).

## Эталон

Ориентируйся на официальный шаблон [deploy/fly](https://github.com/rohitg00/agentmemory/tree/main/deploy/fly):

- multi-stage Dockerfile: `iiidev/iii` + `node:22-slim`
- pin `@agentmemory/agentmemory@0.9.12` и `iii-sdk@0.11.2` через local npm prefix + overrides
- entrypoint как root: iii-config на `0.0.0.0` + `/data`, HMAC в `/data/.hmac`, `gosu node:node agentmemory`
- health: `/agentmemory/livez`
- MCP env: `AGENTMEMORY_URL`, `AGENTMEMORY_SECRET` (не `AGENTMEMORY_HMAC_SECRET`)

## Файлы (UTF-8, LF)

| Путь | Назначение |
|------|------------|
| `deploy/timeweb/Dockerfile` | Образ + awscli + cron |
| `deploy/timeweb/entrypoint.sh` | restore → HMAC → cron → exec agentmemory |
| `deploy/timeweb/backup.sh` | `restore` / `backup`, S3 Timeweb endpoint |
| `deploy/timeweb/.dockerignore` | Исключения build context |
| `docker-compose.yml` | Локальный тест (volume `.data:/data`) |
| `.dockerignore` | Корневой ignore |
| `.env.example` | Шаблон переменных |
| `.gitignore` | `.env`, `.data/` |
| `docs/TIMEWEB_DEPLOY.md` | Инструкция деплоя |
| `docs/CURSOR_CONFIG.md` | MCP для Cursor |
| `README.md` | Ссылка на docs |

## Требования Dockerfile

- **Не** использовать `USER node` до entrypoint (root нужен для chown, cron, aws)
- `ENTRYPOINT` через `tini` → entrypoint.sh
- `EXPOSE 3111` только
- Пакеты: `tini`, `gosu`, `openssl`, `curl`, `tar`, `gzip`, `awscli`, `cron`

## Требования entrypoint.sh

1. `mkdir -p /data`, `chown node:node`
2. Записать deploy `iii-config.yaml` (порты 3111/3112 на `0.0.0.0`, state/stream в `/data`)
3. Если `AWS_S3_BUCKET` задан — `/usr/local/bin/backup.sh restore`
4. Если нет `/data/.hmac` — `openssl rand -hex 32`, вывести **один раз** `AGENTMEMORY_SECRET=...`
5. `export AGENTMEMORY_SECRET=$(cat /data/.hmac)`
6. Если `ENABLE_BACKUPS=true` — cron `0 */6 * * *` → `backup.sh backup`
7. `exec gosu node:node agentmemory "$@"`

## Требования backup.sh

- `AWS_ENDPOINT_URL` default `https://s3.twcstorage.ru`
- `AWS_REGION` default `ru-1`
- **restore:** skip если `ENABLE_AUTO_RESTORE=false` или в `/data` уже есть данные кроме пустого тома
- **backup:** `tar.gz` всего `/data`, upload в `s3://$BUCKET/$PREFIX/`, удалить старые (keep 7)
- Полные S3 URI в `aws s3 cp` / `aws s3 rm`
- Subcommands: `restore`, `backup`

## Запреты

- Не коммитить `AGENTMEMORY_SECRET`, `.env`, ключи S3
- Не использовать устаревший `agentmemory start --hmac-secret`
- Не экспонировать порт 3113 в Apps

## Переменные Timeweb Apps

| Переменная | Пример |
|------------|--------|
| `ENABLE_BACKUPS` | `true` |
| `ENABLE_AUTO_RESTORE` | `true` |
| `AWS_S3_BUCKET` | `my-agentmemory-backups` |
| `AWS_ACCESS_KEY_ID` | из панели S3 |
| `AWS_SECRET_ACCESS_KEY` | секрет |
| `AWS_ENDPOINT_URL` | `https://s3.twcstorage.ru` |
| `AWS_REGION` | `ru-1` |
| `AWS_S3_PREFIX` | `agentmemory-backups` |

Storage: mount **`/data`**. Port: **3111**. Health: **`/agentmemory/livez`**.

## Cursor (~/.cursor/mcp.json)

```json
{
  "mcpServers": {
    "agentmemory": {
      "command": "npx",
      "args": ["-y", "@agentmemory/mcp"],
      "env": {
        "AGENTMEMORY_URL": "https://your-app.timeweb.cloud",
        "AGENTMEMORY_SECRET": "<from-first-boot-logs>"
      }
    }
  }
}
```

## Чеклист

- [ ] Dockerfile собирается
- [ ] `curl http://localhost:3111/agentmemory/livez` локально
- [ ] HMAC в логах первого запуска
- [ ] S3 backup/restore при заданных ключах
- [ ] Документация актуальна

---
