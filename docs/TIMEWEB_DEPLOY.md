# Деплой agentmemory в Timeweb Cloud Apps

Этот репозиторий содержит Docker-образ для [agentmemory](https://github.com/rohitg00/agentmemory) с персистентным томом `/data`, HMAC-аутентификацией и бэкапами в **Timeweb Object Storage** (S3-compatible).

## Что получится

- HTTPS API через домен Timeweb (**80/443** → контейнер **8080**, путь `/agentmemory/*`)
- Секрет `AGENTMEMORY_SECRET` в `/data/.hmac` (генерируется при первом запуске)
- Автобэкап `/data` в S3 каждые 6 часов (опционально)
- Автовосстановление из последнего бэкапа при пустом томе (опционально)

Просмотрщик памяти (порт 3113) **не экспонируется** — только внутри контейнера.

## Предварительные требования

1. Аккаунт [Timeweb Cloud](https://timeweb.cloud)
2. Приложение **Apps** (Docker / Git)
3. Бакет **S3** в Timeweb ([документация](https://timeweb.cloud/docs/s3-storage))
4. Ключи доступа к бакету (Access Key + Secret Key)

## 1. Создайте S3-бакет

В панели Timeweb: **S3 → Создать бакет**.

Запомните:

| Параметр | Значение |
|----------|----------|
| Endpoint | `https://s3.twcstorage.ru` |
| Region | `ru-1` |

Создайте ключи доступа на странице бакета.

## 2. Деплой в Apps

### Вариант A: Docker Compose из Git (рекомендуется)

1. Загрузите репозиторий в GitHub/GitLab.
2. Timeweb Apps → **Создать приложение → Docker Compose**.
3. Укажите репозиторий и ветку. В корне должен быть **`docker-compose.yml`** (без секции `volumes` — это требование Timeweb).
4. В панели Apps → **Storage**: смонтируйте persistent volume в **`/data`** (1+ GB).
5. **Порт контейнера** в панели: **80** (nginx). Не используйте `8080:8080` в compose — ломает маршрутизацию. Health: **`/agentmemory/livez`**.
6. Публичный URL **без порта**: `http://<app>.twc1.net/agentmemory/livez` (Timeweb 80/443 → контейнер **8080**).
7. Опционально в env: `APP_PUBLIC_URL=https://<app>.twc1.net` (для CORS).

Проверка манифеста локально:

```bash
docker compose config
```

Локальный запуск **с** bind-mount (не для Timeweb):

```bash
docker compose -f docker-compose.yml -f docker-compose.local.yml up --build
```

### Вариант B: только Dockerfile (без Compose)

1. Apps → Docker / Git.
2. **Dockerfile path:** `deploy/timeweb/Dockerfile`
3. **Build context:** `deploy/timeweb`
4. Storage → mount **`/data`**, порт **3111**.

### Вариант C: образ из registry

```bash
cd deploy/timeweb
docker build -t your-registry/agentmemory:latest .
docker push your-registry/agentmemory:latest
```

В Apps выберите деплой из образа и укажите тег.

## 3. Настройте приложение в Timeweb Apps

| Параметр | Значение |
|----------|----------|
| Порт контейнера | **80** |
| Health check path | **`/agentmemory/livez`** |
| Grace period | ≥ **60** секунд (cold start) |
| Публичный доступ | `https://<app>.twc1.net/...` **без** `:3111` |
| Storage | Persistent volume, mount **`/data`**, ≥ 1 GB |

Включите **Automatic backups** для тома в панели Storage (дополнительный слой защиты).

### Переменные окружения

| Переменная | Обязательно | Пример | Описание |
|------------|-------------|--------|----------|
| `ENABLE_BACKUPS` | для S3 cron | `true` | Бэкап каждые 6 часов |
| `ENABLE_AUTO_RESTORE` | для restore | `true` | Восстановить из S3 при пустом `/data` |
| `AWS_S3_BUCKET` | да (с S3) | `my-agentmemory-backups` | Имя бакета |
| `AWS_ACCESS_KEY_ID` | да (с S3) | — | Access key |
| `AWS_SECRET_ACCESS_KEY` | да (с S3) | — | Secret key (секрет в панели) |
| `AWS_ENDPOINT_URL` | да | `https://s3.twcstorage.ru` | Endpoint Timeweb S3 |
| `AWS_REGION` | да | `ru-1` | Регион |
| `AWS_S3_PREFIX` | нет | `agentmemory-backups` | Префикс ключей в бакете |
| `BACKUP_KEEP_COUNT` | нет | `7` | Сколько архивов хранить |

**Не задавайте** `AGENTMEMORY_SECRET` в Apps — секрет создаётся в `/data/.hmac` при первом запуске.

Опционально (LLM / embeddings): `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY` — см. [upstream deploy README](https://github.com/rohitg00/agentmemory/blob/main/deploy/README.md).

## 4. Первый запуск — сохраните секрет

После деплоя откройте **логи** приложения. При первом запуске появится блок:

```
================================================================
agentmemory: generated HMAC secret on first boot
AGENTMEMORY_SECRET=<64 hex characters>
Copy this value now. It will not be printed again.
================================================================
```

Скопируйте значение в безопасное место — оно понадобится для Cursor ([CURSOR_CONFIG.md](./CURSOR_CONFIG.md)).

При включённом S3 restore в логах также может быть:

```
=== Checking for S3 backups to restore ===
Restore completed. HMAC secret prefix: ...
```

## 5. Проверка

Замените `<app-url>` и `<secret>`:

```bash
# Через nginx Timeweb (правильно) — без :3111
curl -sv "http://<app>.twc1.net/agentmemory/livez"
curl -sv "https://<app>.twc1.net/agentmemory/livez"

curl -sf -H "Authorization: Bearer <secret>" \
  "https://<app>.twc1.net/agentmemory/livez"
```

Прямой `:3111` на домене часто **не отвечает** — используйте URL без порта.

После деплоя в логах ищите блок `post-start connectivity check` — должны быть `OK :80/livez` и `OK :8080/livez`. Если FAIL — пришлите лог в поддержку Timeweb.

## 6. Подключите Cursor

См. [CURSOR_CONFIG.md](./CURSOR_CONFIG.md).

## Локальная проверка

```bash
cp .env.example .env
# отредактируйте .env при необходимости

docker compose -f docker-compose.yml -f docker-compose.local.yml up --build
curl -sf http://localhost:3111/agentmemory/livez
```

Секрет — в логах контейнера (`AGENTMEMORY_SECRET=...`).

## Ручной бэкап / восстановление

Внутри контейнера:

```bash
/usr/local/bin/backup.sh backup
/usr/local/bin/backup.sh restore
```

Скачать архив с S3 (с локальной машины, с настроенным `aws`):

```bash
export AWS_ENDPOINT_URL=https://s3.twcstorage.ru
export AWS_DEFAULT_REGION=ru-1
aws s3 ls s3://MY_BUCKET/agentmemory-backups/
aws s3 cp s3://MY_BUCKET/agentmemory-backups/agentmemory-backup-YYYYMMDD-HHMMSS.tar.gz ./backup.tar.gz
mkdir -p restored && tar -xzf backup.tar.gz -C restored
```

## Ротация секрета

1. `fly`-аналог: удалите `/data/.hmac` на томе (или через SSH/console Apps).
2. Перезапустите приложение — в логах появится новый `AGENTMEMORY_SECRET`.
3. Обновите `~/.cursor/mcp.json` на всех машинах.

## Troubleshooting

| Симптом | Решение |
|---------|---------|
| Ошибка деплоя Compose без деталей | Уберите `volumes:` из `docker-compose.yml`; том `/data` только через Apps → Storage |
| Health check fails | Увеличьте grace period; cold start ~10–30 с |
| 401 от API | Проверьте `Authorization: Bearer` и секрет из `/data/.hmac` |
| Пустая память после рестарта | Включите том `/data`; проверьте S3 restore в логах |
| S3 upload fails | Проверьте endpoint `https://s3.twcstorage.ru`, region `ru-1`, права ключа |
| Cursor не подключается | `AGENTMEMORY_URL` с `https://`; перезапустите Cursor |

## Версии

По умолчанию в Dockerfile:

- `@agentmemory/agentmemory@0.9.12`
- `iiidev/iii@0.11.2`

Обновление: измените `ARG` в `deploy/timeweb/Dockerfile` и пересоберите образ.
