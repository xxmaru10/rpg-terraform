#!/usr/bin/env bash
# scripts/backup.sh
# Manual or cron-triggered PostgreSQL backup to S3
# Run on EC2 or locally via SSH
#
# On EC2, add to crontab:
#   0 2 * * * /opt/rpg-platform/backup.sh >> /var/log/rpg-backup.log 2>&1

set -euo pipefail

source /etc/rpg-platform.env

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="/tmp/rpg-backup-${TIMESTAMP}.sql.gz"
S3_KEY="backups/postgres/${TIMESTAMP}.sql.gz"

echo "[$TIMESTAMP] Starting backup..."

# Dump and compress
docker exec \
  $(docker ps -qf name=postgres) \
  pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" | \
  gzip > "$BACKUP_FILE"

BACKUP_SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
echo "  Dump complete: $BACKUP_SIZE"

# Upload to S3
aws s3 cp "$BACKUP_FILE" "s3://${S3_BUCKET}/${S3_KEY}" \
  --storage-class STANDARD_IA

echo "  Uploaded: s3://${S3_BUCKET}/${S3_KEY} ✓"

# Keep only last 30 backups in S3
echo "  Pruning old backups..."
aws s3 ls "s3://${S3_BUCKET}/backups/postgres/" | \
  sort | \
  head -n -30 | \
  awk '{print $4}' | \
  while read key; do
    aws s3 rm "s3://${S3_BUCKET}/backups/postgres/${key}"
    echo "  Deleted old backup: $key"
  done

rm -f "$BACKUP_FILE"
echo "  Backup complete ✓"
