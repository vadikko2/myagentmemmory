# Подключение Cursor к agentmemory (Timeweb)

## 1. Получите URL и секрет

- **URL:** `https://<your-app>.timeweb.cloud` (домен из панели Apps)
- **Секрет:** `AGENTMEMORY_SECRET` из логов первого запуска (64 hex-символа)

Секрет хранится на сервере в `/data/.hmac` и попадает в S3-бэкапы вместе с данными.

## 2. Настройте MCP

Отредактируйте `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "agentmemory": {
      "command": "npx",
      "args": ["-y", "@agentmemory/mcp"],
      "env": {
        "AGENTMEMORY_URL": "https://your-app.timeweb.cloud",
        "AGENTMEMORY_SECRET": "paste-64-hex-secret-here"
      }
    }
  }
}
```

Используйте **`AGENTMEMORY_SECRET`**, не `AGENTMEMORY_HMAC_SECRET`.

Опционально — больше инструментов MCP:

```json
"AGENTMEMORY_TOOLS": "all"
```

## 3. Перезапустите Cursor

Полностью закройте и откройте Cursor после изменения `mcp.json`.

## 4. Проверка с терминала

```bash
export AGENTMEMORY_URL="https://your-app.timeweb.cloud"
export AGENTMEMORY_SECRET="your-secret"

curl -sf "${AGENTMEMORY_URL}/agentmemory/livez"

curl -sf -H "Authorization: Bearer ${AGENTMEMORY_SECRET}" \
  "${AGENTMEMORY_URL}/agentmemory/livez"
```

Ожидается ответ со статусом OK / live.

## 5. Проверка в Cursor

1. **Settings → MCP** — сервер `agentmemory` в статусе connected.
2. В чате Agent доступны инструменты памяти (`memory_store`, `memory_recall`, …).

## Локальный agentmemory (для сравнения)

Если daemon запущен локально без секрета:

```json
{
  "mcpServers": {
    "agentmemory": {
      "command": "npx",
      "args": ["-y", "@agentmemory/mcp"],
      "env": {
        "AGENTMEMORY_URL": "http://localhost:3111"
      }
    }
  }
}
```

## Troubleshooting

| Проблема | Что проверить |
|----------|----------------|
| MCP disconnected | URL с `https://`; секрет без пробелов; перезапуск Cursor |
| 401 / auth errors | Секрет совпадает с `/data/.hmac`; заголовок `Bearer` на сервере |
| Timeout | Приложение в Apps запущено; health `/agentmemory/livez` |
| Работало, потом сломалось | Том `/data` потерян — проверьте S3 restore в логах; обновите секрет если `.hmac` пересоздан |
| `npx` медленно | Первый запуск MCP качает пакет; подождите или установите `@agentmemory/mcp` глобально |

## Безопасность

- Не коммитьте секрет в git.
- Не храните секрет в переменных Apps — только в Cursor локально (или в менеджере паролей).
- Timeweb терминирует TLS на edge; не отключайте HTTPS в `AGENTMEMORY_URL`.
