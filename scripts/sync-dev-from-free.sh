#!/usr/bin/env bash
# scripts/sync-dev-from-free.sh
# Downloads the latest PostgreSQL backup from the free/prod S3 bucket
# and restores it into the dev EC2 instance.
#
# Usage:
#   ./sync-dev-from-free.sh <DEV_EC2_IP> [--ssh-key ~/.ssh/rpg-platform]
#
# Requirements:
#   - dev EC2 IAM role must have read access to FREE_S3_BACKUP_BUCKET
#     (managed via Terraform: free_backup_bucket_name variable in envs/dev)
#   - AWS CLI configured locally with sufficient permissions to run the script

set -euo pipefail

# ── Args ──────────────────────────────────────────────────────────────────────
DEV_EC2_IP="${1:-}"
SSH_KEY="${2:-~/.ssh/rpg-platform}"

if [ -z "$DEV_EC2_IP" ]; then
  echo "Usage: $0 <DEV_EC2_IP> [ssh-key-path]"
  echo "  DEV_EC2_IP  — public IP or DNS of the dev EC2 instance"
  echo "  ssh-key     — path to SSH private key (default: ~/.ssh/rpg-platform)"
  exit 1
fi

# ── Config ────────────────────────────────────────────────────────────────────
# Free/prod backup bucket (must match free env terraform.tfvars)
FREE_S3_BACKUP_BUCKET="${FREE_S3_BACKUP_BUCKET:-rpg-platform-postgres-backups-306337361114}"

echo "=== Dev DB Sync from Free/Prod ==="
echo "  Target instance : $DEV_EC2_IP"
echo "  Source bucket   : s3://$FREE_S3_BACKUP_BUCKET/backups/postgres/"
echo ""

# ── Find latest backup ────────────────────────────────────────────────────────
echo "[1/4] Finding latest backup in S3..."
LATEST=$(aws s3 ls "s3://${FREE_S3_BACKUP_BUCKET}/backups/postgres/" \
  | sort \
  | tail -1 \
  | awk '{print $4}')

if [ -z "$LATEST" ]; then
  echo "ERROR: No backups found in s3://${FREE_S3_BACKUP_BUCKET}/backups/postgres/"
  exit 1
fi

echo "  Latest backup: $LATEST"
echo ""

# ── Confirm before wiping dev DB ──────────────────────────────────────────────
read -r -p "[!] This will DROP and recreate the dev database. Continue? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

# ── Restore on dev EC2 ────────────────────────────────────────────────────────
echo "[2/4] Connecting to dev EC2 and downloading backup..."

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ec2-user@${DEV_EC2_IP}" bash <<ENDSSH
set -euo pipefail

source /etc/rpg-platform.env

echo "[2/4] Downloading s3://${FREE_S3_BACKUP_BUCKET}/backups/postgres/${LATEST}..."
aws s3 cp "s3://${FREE_S3_BACKUP_BUCKET}/backups/postgres/${LATEST}" /tmp/sync-restore.sql.gz

echo "[3/4] Dropping and recreating dev database..."
CONTAINER=\$(docker ps --format '{{.ID}} {{.Names}}' | grep postgres | grep -v dev | awk '{print \$1}' | head -1)
# Try both naming conventions (dev container may be named differently)
if [ -z "\$CONTAINER" ]; then
  CONTAINER=\$(docker ps --format '{{.ID}} {{.Names}}' | grep postgres | awk '{print \$1}' | head -1)
fi

if [ -z "\$CONTAINER" ]; then
  echo "ERROR: No running Postgres container found"
  exit 1
fi

docker exec "\$CONTAINER" psql -U "\$POSTGRES_USER" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '\$POSTGRES_DB' AND pid <> pg_backend_pid();" postgres
docker exec "\$CONTAINER" psql -U "\$POSTGRES_USER" -c "DROP DATABASE IF EXISTS \$POSTGRES_DB;" postgres
docker exec "\$CONTAINER" psql -U "\$POSTGRES_USER" -c "CREATE DATABASE \$POSTGRES_DB;" postgres

echo "[4/4] Restoring backup..."
gunzip -c /tmp/sync-restore.sql.gz | docker exec -i "\$CONTAINER" psql -U "\$POSTGRES_USER" \$POSTGRES_DB

rm -f /tmp/sync-restore.sql.gz
echo ""
echo "=== Restore complete ==="
echo "  Database : \$POSTGRES_DB"
echo "  Source   : ${LATEST}"
ENDSSH

echo ""
echo "Done. Dev database now mirrors free/prod as of: $LATEST"
