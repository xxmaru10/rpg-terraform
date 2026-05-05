#!/usr/bin/env bash
# scripts/migrate-supabase.sh
# Migrates your Supabase PostgreSQL database and Storage to:
#   - PostgreSQL running on EC2 (via Docker)
#   - AWS S3 (for files/assets)
#
# Usage:
#   ./migrate-supabase.sh \
#     --supabase-url "https://yourproject.supabase.co" \
#     --supabase-db-host "db.yourproject.supabase.co" \
#     --supabase-db-password "your-db-password" \
#     --ec2-ip "1.2.3.4"
#
# Prerequisites:
#   - pg_dump installed locally (brew install postgresql / apt install postgresql-client)
#   - AWS CLI configured
#   - EC2 instance running (terraform apply done)
#   - SSH key available

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ──────────────────────────────────────────────
# Parse arguments
# ──────────────────────────────────────────────
SUPABASE_URL=""
SUPABASE_DB_HOST=""
SUPABASE_DB_PASSWORD=""
SUPABASE_DB_USER="postgres"
SUPABASE_DB_NAME="postgres"
SUPABASE_DB_PORT="5432"
EC2_IP=""
SSH_KEY="${SSH_KEY_PATH:-~/.ssh/rpg-platform}"
ENV="free"
SKIP_DB=false
SKIP_STORAGE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --supabase-url)         SUPABASE_URL="$2";         shift 2 ;;
    --supabase-db-host)     SUPABASE_DB_HOST="$2";     shift 2 ;;
    --supabase-db-password) SUPABASE_DB_PASSWORD="$2"; shift 2 ;;
    --supabase-db-user)     SUPABASE_DB_USER="$2";     shift 2 ;;
    --supabase-db-name)     SUPABASE_DB_NAME="$2";     shift 2 ;;
    --ec2-ip)               EC2_IP="$2";               shift 2 ;;
    --ssh-key)              SSH_KEY="$2";              shift 2 ;;
    --env)                  ENV="$2";                  shift 2 ;;
    --skip-db)              SKIP_DB=true;              shift ;;
    --skip-storage)         SKIP_STORAGE=true;         shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ──────────────────────────────────────────────
# Validate
# ──────────────────────────────────────────────
if [ -z "$EC2_IP" ]; then
  echo ">>> Auto-detecting EC2 IP from Terraform..."
  EC2_IP=$(cd "$SCRIPT_DIR/../envs/$ENV" && terraform output -raw instance_public_ip 2>/dev/null || echo "")
fi

if [ -z "$EC2_IP" ]; then
  echo "ERROR: Could not determine EC2 IP. Pass --ec2-ip or run terraform apply first."
  exit 1
fi

if [ -z "$SUPABASE_DB_HOST" ] && [ -z "$SUPABASE_URL" ]; then
  echo "ERROR: Provide --supabase-db-host or --supabase-url"
  exit 1
fi

# Extract DB host from URL if not provided
if [ -z "$SUPABASE_DB_HOST" ] && [ -n "$SUPABASE_URL" ]; then
  PROJECT_REF=$(echo "$SUPABASE_URL" | sed 's|https://\([^.]*\)\.supabase\.co.*|\1|')
  SUPABASE_DB_HOST="db.${PROJECT_REF}.supabase.co"
fi

DUMP_FILE="/tmp/supabase-dump-$(date +%Y%m%d-%H%M%S).sql"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     RPG Platform — Supabase Migration                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Supabase DB  : $SUPABASE_DB_HOST"
echo "  EC2 Target   : $EC2_IP"
echo "  Dump file    : $DUMP_FILE"
echo "  Skip DB      : $SKIP_DB"
echo "  Skip Storage : $SKIP_STORAGE"
echo ""
read -p "Proceed? (y/N): " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ──────────────────────────────────────────────
# PHASE 1: Database migration
# ──────────────────────────────────────────────
if [ "$SKIP_DB" = false ]; then
  echo ""
  echo "════════════════════════════════════════"
  echo " PHASE 1: Database Migration"
  echo "════════════════════════════════════════"

  if [ -z "$SUPABASE_DB_PASSWORD" ]; then
    read -sp "Supabase DB password (from Supabase dashboard > Settings > Database): " SUPABASE_DB_PASSWORD
    echo ""
  fi

  # 1a. Dump from Supabase
  echo ">>> Dumping Supabase database (this may take a few minutes)..."
  PGPASSWORD="$SUPABASE_DB_PASSWORD" pg_dump \
    --host="$SUPABASE_DB_HOST" \
    --port="$SUPABASE_DB_PORT" \
    --username="$SUPABASE_DB_USER" \
    --dbname="$SUPABASE_DB_NAME" \
    --no-owner \
    --no-acl \
    --format=plain \
    --schema=public \
    --exclude-schema=auth \
    --exclude-schema=storage \
    --exclude-schema=realtime \
    --exclude-schema=graphql \
    --exclude-schema=graphql_public \
    --file="$DUMP_FILE"

  DUMP_SIZE=$(du -sh "$DUMP_FILE" | cut -f1)
  echo "    Dump complete: $DUMP_FILE ($DUMP_SIZE) ✓"

  # 1b. Copy dump to EC2
  echo ">>> Copying dump to EC2..."
  scp -i "$SSH_KEY" \
      -o StrictHostKeyChecking=no \
      "$DUMP_FILE" \
      "ec2-user@$EC2_IP:/tmp/supabase-dump.sql"
  echo "    Copied ✓"

  # 1c. Get DB credentials from EC2
  echo ">>> Restoring database on EC2..."
  ssh -i "$SSH_KEY" \
      -o StrictHostKeyChecking=no \
      "ec2-user@$EC2_IP" << 'REMOTE'

set -e
source /etc/rpg-platform.env

echo "--- Waiting for PostgreSQL to be healthy ---"
for i in {1..30}; do
  if docker exec $(docker ps -qf name=postgres) pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" 2>/dev/null; then
    echo "    PostgreSQL ready ✓"
    break
  fi
  echo "    Waiting... ($i/30)"
  sleep 5
done

echo "--- Restoring dump ---"
# Clean existing schema first (idempotent migration)
docker exec -i \
  $(docker ps -qf name=postgres) \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"

# Restore
docker exec -i \
  $(docker ps -qf name=postgres) \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  < /tmp/supabase-dump.sql

echo "--- Verify restore ---"
TABLE_COUNT=$(docker exec $(docker ps -qf name=postgres) \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t \
  -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
echo "    Tables restored: $TABLE_COUNT ✓"

rm -f /tmp/supabase-dump.sql
echo "--- DB migration complete ✓ ---"
REMOTE

  echo "    Database restored ✓"
  rm -f "$DUMP_FILE"
fi

# ──────────────────────────────────────────────
# PHASE 2: Storage migration (Supabase → S3)
# ──────────────────────────────────────────────
if [ "$SKIP_STORAGE" = false ] && [ -n "$SUPABASE_URL" ]; then
  echo ""
  echo "════════════════════════════════════════"
  echo " PHASE 2: Storage Migration"
  echo "════════════════════════════════════════"

  read -sp "Supabase service role key (from Supabase dashboard > Settings > API): " SUPABASE_KEY
  echo ""

  S3_BUCKET=$(cd "$SCRIPT_DIR/../envs/$ENV" && terraform output -raw s3_bucket_name 2>/dev/null || echo "")

  if [ -z "$S3_BUCKET" ]; then
    echo "WARN: Could not determine S3 bucket. Skipping storage migration."
  else
    echo ">>> Listing Supabase storage buckets..."
    BUCKETS=$(curl -s \
      -H "Authorization: Bearer $SUPABASE_KEY" \
      -H "Content-Type: application/json" \
      "${SUPABASE_URL}/storage/v1/bucket" | \
      python3 -c "import sys,json; [print(b['name']) for b in json.load(sys.stdin)]" 2>/dev/null || echo "")

    if [ -z "$BUCKETS" ]; then
      echo "    No storage buckets found (or API key issue). Skipping."
    else
      echo "    Found buckets: $BUCKETS"

      TMP_STORAGE="/tmp/supabase-storage-$$"
      mkdir -p "$TMP_STORAGE"

      for BUCKET in $BUCKETS; do
        echo ">>> Migrating bucket: $BUCKET"
        mkdir -p "$TMP_STORAGE/$BUCKET"

        # List files in bucket
        FILES=$(curl -s \
          -H "Authorization: Bearer $SUPABASE_KEY" \
          "${SUPABASE_URL}/storage/v1/object/list/${BUCKET}" \
          -X POST \
          -H "Content-Type: application/json" \
          -d '{"limit":1000,"offset":0}' | \
          python3 -c "import sys,json; [print(f['name']) for f in json.load(sys.stdin) if f.get('name')]" 2>/dev/null || echo "")

        FILE_COUNT=0
        for FILE in $FILES; do
          # Download from Supabase
          curl -s \
            -H "Authorization: Bearer $SUPABASE_KEY" \
            "${SUPABASE_URL}/storage/v1/object/${BUCKET}/${FILE}" \
            -o "$TMP_STORAGE/$BUCKET/$FILE" 2>/dev/null && FILE_COUNT=$((FILE_COUNT+1)) || true
        done

        # Upload to S3
        if [ $FILE_COUNT -gt 0 ]; then
          aws s3 sync "$TMP_STORAGE/$BUCKET/" "s3://$S3_BUCKET/uploads/$BUCKET/"
          echo "    Migrated $FILE_COUNT files from $BUCKET ✓"
        else
          echo "    No files in $BUCKET"
        fi
      done

      rm -rf "$TMP_STORAGE"
      echo "    Storage migration complete ✓"
    fi
  fi
fi

# ──────────────────────────────────────────────
# Done
# ──────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Migration Complete!                                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Next steps:"
echo "  1. Update your NestJS backend DATABASE_URL to point to EC2 Postgres"
echo "     DATABASE_URL=postgresql://rpgadmin:<password>@localhost:5432/rpgplatform"
echo ""
echo "  2. Update your Next.js NEXT_PUBLIC_API_URL in Vercel:"
echo "     NEXT_PUBLIC_API_URL=http://$EC2_IP/api"
echo ""
echo "  3. Update your WebRTC TURN server config in frontend:"
echo "     { urls: 'turn:$EC2_IP:3478', ... }"
echo ""
echo "  4. Verify your app is working, then disable Supabase project"
echo ""
