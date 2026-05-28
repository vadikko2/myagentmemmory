#!/bin/sh
# Backup and restore /data to Timeweb S3-compatible Object Storage.
# Usage: backup.sh restore | backup

set -eu

DATA_DIR="${AGENTMEMORY_DATA_DIR:-/data}"
BACKUP_DIR="/tmp/backups"
BACKUP_NAME="agentmemory-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
KEEP_COUNT="${BACKUP_KEEP_COUNT:-7}"

export AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-https://s3.twcstorage.ru}"
export AWS_DEFAULT_REGION="${AWS_REGION:-ru-1}"

S3_PREFIX="${AWS_S3_PREFIX:-agentmemory-backups}"

aws_s3() {
  aws --endpoint-url "$AWS_ENDPOINT_URL" s3 "$@"
}

s3_base_uri() {
  if [ -z "${AWS_S3_BUCKET:-}" ]; then
    echo "AWS_S3_BUCKET is not set" >&2
    return 1
  fi
  printf 's3://%s/%s' "$AWS_S3_BUCKET" "$S3_PREFIX"
}

data_has_content() {
  if [ ! -d "$DATA_DIR" ]; then
    return 1
  fi
  # Skip restore when .hmac exists and there is other persisted state.
  if [ -f "$DATA_DIR/.hmac" ]; then
    found="$(find "$DATA_DIR" -mindepth 1 -maxdepth 1 ! -name '.hmac' 2>/dev/null | head -n 1 || true)"
    if [ -n "$found" ]; then
      return 0
    fi
  fi
  return 1
}

restore_from_s3() {
  echo "=== Checking for S3 backups to restore ==="

  if [ "${ENABLE_AUTO_RESTORE:-true}" = "false" ]; then
    echo "Auto-restore disabled (ENABLE_AUTO_RESTORE=false). Skipping."
    return 0
  fi

  if [ -z "${AWS_S3_BUCKET:-}" ]; then
    echo "AWS_S3_BUCKET not set. Skipping restore."
    return 0
  fi

  if data_has_content; then
    echo "Data already present in $DATA_DIR. Skipping restore."
    return 0
  fi

  S3_URI="$(s3_base_uri)"
  echo "No existing data in $DATA_DIR. Looking for backups in ${S3_URI}/"

  LATEST_BACKUP="$(aws_s3 ls "${S3_URI}/" 2>/dev/null | awk '{print $4}' | grep '\.tar\.gz$' | sort | tail -n 1 || true)"
  if [ -z "$LATEST_BACKUP" ]; then
    echo "No backups found in S3. Starting fresh."
    return 0
  fi

  mkdir -p "$BACKUP_DIR"
  BACKUP_FILE="$BACKUP_DIR/restore.tar.gz"
  S3_OBJECT="${S3_URI}/${LATEST_BACKUP}"

  echo "Found backup: $LATEST_BACKUP"
  echo "Downloading $S3_OBJECT ..."

  if ! aws_s3 cp "$S3_OBJECT" "$BACKUP_FILE"; then
    echo "Failed to download backup from S3." >&2
    return 1
  fi

  mkdir -p "$DATA_DIR"
  echo "Extracting to $DATA_DIR ..."
  if ! tar -xzf "$BACKUP_FILE" -C "$DATA_DIR"; then
    echo "Failed to extract backup." >&2
    rm -f "$BACKUP_FILE"
    return 1
  fi

  rm -f "$BACKUP_FILE"
  chown -R node:node "$DATA_DIR" 2>/dev/null || true

  if [ -f "$DATA_DIR/.hmac" ]; then
    secret_preview="$(head -c 16 "$DATA_DIR/.hmac" 2>/dev/null || true)"
    echo "Restore completed. HMAC secret prefix: ${secret_preview}..."
  else
    echo "Restore completed (no .hmac in archive)."
  fi

  return 0
}

create_backup() {
  echo "=== Starting agentmemory backup ==="

  if [ -z "${AWS_S3_BUCKET:-}" ]; then
    echo "AWS_S3_BUCKET not set. Skipping backup." >&2
    return 1
  fi

  if [ ! -d "$DATA_DIR" ] || [ -z "$(ls -A "$DATA_DIR" 2>/dev/null || true)" ]; then
    echo "No data to backup in $DATA_DIR. Skipping."
    return 0
  fi

  S3_URI="$(s3_base_uri)"
  mkdir -p "$BACKUP_DIR"
  ARCHIVE="$BACKUP_DIR/$BACKUP_NAME"
  S3_OBJECT="${S3_URI}/${BACKUP_NAME}"

  echo "Backup file: $BACKUP_NAME"
  echo "S3 destination: $S3_OBJECT"

  if ! tar -czf "$ARCHIVE" \
    -C "$DATA_DIR" \
    --exclude='*.tmp' \
    --exclude='.tmp' \
    .; then
    echo "Failed to create backup archive." >&2
    return 1
  fi

  if ! aws_s3 cp "$ARCHIVE" "$S3_OBJECT"; then
    echo "Failed to upload backup to S3." >&2
    rm -f "$ARCHIVE"
    return 1
  fi

  rm -f "$ARCHIVE"
  echo "Backup completed: $S3_OBJECT"

  echo "Cleaning up old backups (keeping last ${KEEP_COUNT}) ..."
  aws_s3 ls "${S3_URI}/" 2>/dev/null | awk '{print $4}' | grep '\.tar\.gz$' | sort | head -n "-${KEEP_COUNT}" | while read -r old_backup; do
    [ -z "$old_backup" ] && continue
    echo "Removing old backup: $old_backup"
    aws_s3 rm "${S3_URI}/${old_backup}" || true
  done

  echo "Cleanup completed"
  return 0
}

case "${1:-}" in
  restore)
    restore_from_s3
    ;;
  backup)
    create_backup
    ;;
  *)
    echo "Usage: $0 restore|backup" >&2
    exit 1
    ;;
esac
