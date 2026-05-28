#!/bin/sh
# Timeweb Cloud Apps entrypoint for agentmemory.
# Runs as root: chown /data, S3 restore, HMAC bootstrap, cron, then gosu node.

set -eu

DATA_DIR="${AGENTMEMORY_DATA_DIR:-/data}"
HMAC_FILE="${AGENTMEMORY_HMAC_FILE:-/data/.hmac}"
RUN_AS="node:node"
III_CONFIG="/opt/agentmemory/node_modules/@agentmemory/agentmemory/dist/iii-config.yaml"

# Timeweb Apps: set PORT=3111 in compose; platform nginx proxies 80/443 -> this port.
HTTP_PORT="${PORT:-${III_REST_PORT:-3111}}"
STREAM_PORT="${III_STREAMS_PORT:-3112}"
HTTP_HOST="0.0.0.0"

mkdir -p "$DATA_DIR"
chown -R "$RUN_AS" "$DATA_DIR"

# Optional public URL for CORS (e.g. https://your-app.twc1.net from Timeweb panel)
CORS_PUBLIC_HTTP=""
CORS_PUBLIC_HTTPS=""
if [ -n "${APP_PUBLIC_URL:-}" ]; then
  case "$APP_PUBLIC_URL" in
    http://*) CORS_PUBLIC_HTTP="$APP_PUBLIC_URL" ;;
    https://*) CORS_PUBLIC_HTTPS="$APP_PUBLIC_URL" ;;
    *) CORS_PUBLIC_HTTPS="https://${APP_PUBLIC_URL}" ;;
  esac
  if [ -n "$CORS_PUBLIC_HTTPS" ] && [ -z "$CORS_PUBLIC_HTTP" ]; then
    CORS_PUBLIC_HTTP="$(printf '%s' "$CORS_PUBLIC_HTTPS" | sed 's|^https://|http://|')"
  fi
  if [ -n "$CORS_PUBLIC_HTTP" ] && [ -z "$CORS_PUBLIC_HTTPS" ]; then
    CORS_PUBLIC_HTTPS="$(printf '%s' "$CORS_PUBLIC_HTTP" | sed 's|^http://|https://|')"
  fi
fi

cat > "$III_CONFIG" <<EOF
workers:
  - name: iii-http
    config:
      port: ${HTTP_PORT}
      host: ${HTTP_HOST}
      default_timeout: 180000
      cors:
        allowed_origins:
          - "http://localhost:${HTTP_PORT}"
          - "http://localhost:3113"
          - "http://127.0.0.1:${HTTP_PORT}"
          - "http://127.0.0.1:3113"
$( [ -n "$CORS_PUBLIC_HTTP" ] && printf '          - "%s"\n' "$CORS_PUBLIC_HTTP" )
$( [ -n "$CORS_PUBLIC_HTTPS" ] && printf '          - "%s"\n' "$CORS_PUBLIC_HTTPS" )
        allowed_methods: [GET, POST, PUT, DELETE, OPTIONS]
  - name: iii-state
    config:
      adapter:
        name: kv
        config:
          store_method: file_based
          file_path: /data/state_store.db
  - name: iii-queue
    config:
      adapter:
        name: builtin
  - name: iii-pubsub
    config:
      adapter:
        name: local
  - name: iii-cron
    config:
      adapter:
        name: kv
  - name: iii-stream
    config:
      port: ${STREAM_PORT}
      host: ${HTTP_HOST}
      adapter:
        name: kv
        config:
          store_method: file_based
          file_path: /data/stream_store
  - name: iii-observability
    config:
      enabled: true
      service_name: agentmemory
      exporter: memory
      sampling_ratio: 1.0
      metrics_enabled: true
      logs_enabled: true
      logs_console_output: true
EOF
chown "$RUN_AS" "$III_CONFIG"

echo "agentmemory: listening on ${HTTP_HOST}:${HTTP_PORT} (Timeweb nginx uses 80/443 -> ${HTTP_PORT})"

if [ -n "${AWS_S3_BUCKET:-}" ]; then
  /usr/local/bin/backup.sh restore || echo "backup.sh restore: skipped or failed (continuing)"
fi

if [ ! -s "$HMAC_FILE" ]; then
  SECRET="$(openssl rand -hex 32)"
  umask 077
  printf '%s\n' "$SECRET" > "$HMAC_FILE"
  chmod 600 "$HMAC_FILE"
  chown "$RUN_AS" "$HMAC_FILE"
  echo "================================================================"
  echo "agentmemory: generated HMAC secret on first boot"
  echo "AGENTMEMORY_SECRET=$SECRET"
  echo "Copy this value now. It will not be printed again."
  echo "Stored at: $HMAC_FILE (chmod 600)"
  echo "To rotate: delete $HMAC_FILE on the persistent volume and restart."
  echo "================================================================"
else
  echo "agentmemory: using existing HMAC secret at $HMAC_FILE"
fi

AGENTMEMORY_SECRET="$(cat "$HMAC_FILE")"
export AGENTMEMORY_SECRET

if [ "${ENABLE_BACKUPS:-false}" = "true" ] && [ -n "${AWS_S3_BUCKET:-}" ]; then
  echo "0 */6 * * * root /usr/local/bin/backup.sh backup >> /var/log/backup.log 2>&1" > /etc/cron.d/agentmemory-backup
  chmod 0644 /etc/cron.d/agentmemory-backup
  cron
  echo "agentmemory: S3 backup scheduler started (every 6 hours)"
else
  echo "agentmemory: automatic S3 backups disabled (set ENABLE_BACKUPS=true and AWS_S3_BUCKET)"
fi

exec gosu "$RUN_AS" agentmemory "$@"
