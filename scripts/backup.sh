#!/usr/bin/env bash
# scripts/backup.sh
# Manual or cron-triggered PostgreSQL backup to S3
# Run on EC2 or locally via SSH
#
# On EC2, scheduled via systemd timer (rpg-backup.timer):
#   Every 3 days at 02:00 UTC
#   Logs: journalctl -u rpg-backup.service

set -euo pipefail

# Ensure cron can find `docker` and `aws` commands
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

source /etc/rpg-platform.env

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="/tmp/rpg-backup-${TIMESTAMP}.sql.gz"
S3_KEY="backups/postgres/${TIMESTAMP}.sql.gz"

# Guard: skip if Postgres container is not running (excludes dev containers)
CONTAINER=$(docker ps --format '{{.ID}} {{.Names}}' | grep postgres | grep -v dev | awk '{print $1}' | head -1)
if [ -z "$CONTAINER" ]; then
  echo "[$TIMESTAMP] Postgres not running, skipping"
  exit 0
fi

echo "[$TIMESTAMP] Starting backup..."

# Dump and compress
docker exec "$CONTAINER" \
  pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" | \
  gzip > "$BACKUP_FILE"

BACKUP_SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
echo "  Dump complete: $BACKUP_SIZE"

# Upload to S3
aws s3 cp "$BACKUP_FILE" "s3://${S3_BACKUP_BUCKET}/${S3_KEY}" \
  --storage-class STANDARD_IA

echo "  Uploaded: s3://${S3_BACKUP_BUCKET}/${S3_KEY} ✓"

# Cleanup: S3 lifecycle handles retention (15 days), no script-side pruning needed
rm -f "$BACKUP_FILE"
echo "  Backup complete ✓"
