#!/bin/bash
# user_data.sh.tpl — runs once on first boot
# Bootstraps Docker, mounts EBS, writes env file
# NOTE: Does NOT start the app stack — deploy.sh does that after
#       pushing images and configs to S3/ECR

set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

echo "=== RPG Platform Bootstrap Starting ==="

dnf update -y
dnf install -y docker git unzip

mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

DATA_DEVICE="/dev/xvdf"
DATA_MOUNT="/data"

echo "Waiting for EBS volume at $${DATA_DEVICE}..."
for i in {1..24}; do
  if [ -b "$${DATA_DEVICE}" ]; then
    echo "EBS volume found"
    break
  fi
  sleep 5
done

if [ ! -b "$${DATA_DEVICE}" ]; then
  echo "ERROR: EBS volume $${DATA_DEVICE} never appeared"
  exit 1
fi

if ! blkid "$${DATA_DEVICE}" &>/dev/null; then
  mkfs -t xfs "$${DATA_DEVICE}"
fi

mkdir -p "$${DATA_MOUNT}"

if ! mountpoint -q "$${DATA_MOUNT}"; then
  mount "$${DATA_DEVICE}" "$${DATA_MOUNT}"
fi

UUID=$(blkid -s UUID -o value "$${DATA_DEVICE}")
if ! grep -q "$${UUID}" /etc/fstab; then
  echo "UUID=$${UUID} $${DATA_MOUNT} xfs defaults,nofail 0 2" >> /etc/fstab
fi

mkdir -p "$${DATA_MOUNT}"/{postgres,uploads,coturn-logs}
chown -R 999:999 "$${DATA_MOUNT}/postgres"

cat > /etc/rpg-platform.env <<EOF
PROJECT=${project}
ENV=${env}
POSTGRES_DB=${db_name}
POSTGRES_USER=${db_user}
POSTGRES_PASSWORD=${db_password}
DATABASE_URL=postgresql://${db_user}:${db_password}@postgres:5432/${db_name}
TURN_SECRET=${turn_secret}
TURN_REALM=${domain}
AWS_REGION=${aws_region}
S3_BUCKET=${s3_bucket}
NEST_API_PORT=${nest_api_port}
NODE_ENV=production
SUPABASE_URL=${supabase_url}
SUPABASE_KEY=${supabase_key}
EOF

chmod 600 /etc/rpg-platform.env
chown ec2-user:ec2-user /etc/rpg-platform.env

mkdir -p /opt/rpg-platform
chown ec2-user:ec2-user /opt/rpg-platform

cat > /etc/systemd/system/rpg-platform.service <<'SYSTEMD'
[Unit]
Description=RPG Platform Docker Stack
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/rpg-platform
EnvironmentFile=/etc/rpg-platform.env
ExecStart=/usr/local/lib/docker/cli-plugins/docker-compose --env-file /etc/rpg-platform.env up -d
ExecStop=/usr/local/lib/docker/cli-plugins/docker-compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload

cat > /opt/rpg-platform/backup.sh <<'BACKUP'
#!/bin/bash
source /etc/rpg-platform.env
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="/tmp/rpg-backup-$TIMESTAMP.sql.gz"
CONTAINER=$(docker ps -qf name=postgres)
if [ -z "$CONTAINER" ]; then
  echo "[$TIMESTAMP] Postgres not running, skipping"
  exit 0
fi
docker exec "$CONTAINER" pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" | \
  gzip > "$BACKUP_FILE"
aws s3 cp "$BACKUP_FILE" "s3://$S3_BUCKET/backups/postgres/$TIMESTAMP.sql.gz" \
  --storage-class STANDARD_IA
rm -f "$BACKUP_FILE"
echo "[$TIMESTAMP] Backup complete"
BACKUP

chmod +x /opt/rpg-platform/backup.sh
echo "0 2 * * * /opt/rpg-platform/backup.sh >> /var/log/rpg-backup.log 2>&1" | crontab -

echo "=== Bootstrap Complete ==="
echo "Instance ready. Run deploy.sh from local machine to push app."