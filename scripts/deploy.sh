#!/usr/bin/env bash
# scripts/deploy.sh
# Build Docker images, push to ECR, upload configs to S3, restart stack on EC2
#
# Usage:
#   ./deploy.sh                          # Deploy backend only
#   ./deploy.sh --service backend        # Specific service
#   ./deploy.sh --service all            # All services
#   ./deploy.sh --skip-build             # Skip Docker build (re-deploy configs only)
#   ./deploy.sh --env prod               # Target environment

set -euo pipefail

# ──────────────────────────────────────────────
# Defaults
# ──────────────────────────────────────────────
ENV="${DEPLOY_ENV:-free}"
SERVICE="backend"
SKIP_BUILD=false
REGION="${AWS_REGION:-us-east-1}"
PROJECT="${PROJECT:-rpg-platform}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --env)       ENV="$2";     shift 2 ;;
    --service)   SERVICE="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# ──────────────────────────────────────────────
# Resolve infra outputs
# ──────────────────────────────────────────────
echo ">>> Reading Terraform outputs for env: $ENV"
cd "$REPO_ROOT/envs/$ENV"

INSTANCE_IP=$(terraform output -raw instance_public_ip 2>/dev/null || echo "")
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

if [ -z "$INSTANCE_IP" ]; then
  echo "ERROR: Could not get instance IP from Terraform outputs."
  echo "       Run 'terraform apply' first in envs/$ENV/"
  exit 1
fi

echo "  Instance IP : $INSTANCE_IP"
echo "  S3 Bucket   : $S3_BUCKET"
echo "  ECR         : $ECR_REGISTRY"
echo ""

# ──────────────────────────────────────────────
# 1. Docker login to ECR
# ──────────────────────────────────────────────
echo ">>> Authenticating with ECR..."
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"

# ──────────────────────────────────────────────
# 2. Build and push images
# ──────────────────────────────────────────────
build_and_push() {
  local SERVICE_NAME=$1
  local DOCKERFILE_PATH=$2
  local CONTEXT_PATH=$3
  local ECR_REPO="${PROJECT}-rpg-${SERVICE_NAME}"
  local IMAGE_TAG="${ECR_REGISTRY}/${ECR_REPO}:latest"
  local GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "nogit")
  local SHA_TAG="${ECR_REGISTRY}/${ECR_REPO}:${GIT_SHA}"

  echo ">>> Building $SERVICE_NAME..."
  docker build \
    --platform linux/amd64 \
    --file "$DOCKERFILE_PATH" \
    --tag "$IMAGE_TAG" \
    --tag "$SHA_TAG" \
    --label "git-sha=$GIT_SHA" \
    --label "built-at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --cache-from "$IMAGE_TAG" \
    "$CONTEXT_PATH"

  echo ">>> Pushing $SERVICE_NAME to ECR..."
  docker push "$IMAGE_TAG"
  docker push "$SHA_TAG"
  echo "    Pushed: $IMAGE_TAG ✓"
}

if [ "$SKIP_BUILD" = false ]; then
  case $SERVICE in
    backend|all)
      # Expects Dockerfile at ../../apps/backend/Dockerfile (your NestJS repo)
      BACKEND_PATH="${REPO_ROOT}/../backend"
      if [ -d "$BACKEND_PATH" ]; then
        build_and_push "backend" "$BACKEND_PATH/Dockerfile" "$BACKEND_PATH"
      else
        echo "WARN: Backend repo not found at $BACKEND_PATH"
        echo "      Set BACKEND_PATH or put backend/ next to infra/"
      fi
      ;;
  esac
fi

# ──────────────────────────────────────────────
# 3. Upload deploy configs to S3
#    EC2 pulls these on startup and on update
# ──────────────────────────────────────────────
echo ">>> Uploading configs to S3..."

# Generate docker-compose with resolved ECR image
BACKEND_IMAGE="${ECR_REGISTRY}/${PROJECT}-rpg-backend:latest"

sed "s|your-ecr-repo/rpg-backend:latest|${BACKEND_IMAGE}|g" \
  "$REPO_ROOT/docker/docker-compose.yml" > /tmp/docker-compose-resolved.yml

aws s3 cp /tmp/docker-compose-resolved.yml "s3://${S3_BUCKET}/deploy/docker-compose.yml"
aws s3 cp "$REPO_ROOT/docker/nginx/nginx.conf" "s3://${S3_BUCKET}/deploy/nginx.conf"
aws s3 cp "$REPO_ROOT/docker/coturn/turnserver.conf" "s3://${S3_BUCKET}/deploy/turnserver.conf"

echo "    Configs uploaded ✓"

# ──────────────────────────────────────────────
# 4. Pull new images and restart stack on EC2
# ──────────────────────────────────────────────
echo ">>> Deploying to EC2 at $INSTANCE_IP..."

SSH_KEY="${SSH_KEY_PATH:-~/.ssh/rpg-platform}"

ssh -i "$SSH_KEY" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=30 \
    "ec2-user@$INSTANCE_IP" << 'REMOTE'

set -e
echo "--- Remote: pulling latest configs from S3 ---"

# Get S3 bucket from env file
source /etc/rpg-platform.env

aws s3 cp "s3://${S3_BUCKET}/deploy/docker-compose.yml" /opt/rpg-platform/docker-compose.yml
aws s3 cp "s3://${S3_BUCKET}/deploy/nginx.conf" /opt/rpg-platform/nginx.conf
aws s3 cp "s3://${S3_BUCKET}/deploy/turnserver.conf" /opt/rpg-platform/turnserver.conf

echo "--- Remote: logging into ECR ---"
REGION=$(aws configure get region || echo "us-east-1")
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

echo "--- Remote: pulling new images ---"
cd /opt/rpg-platform
docker compose pull backend

echo "--- Remote: rolling restart (zero downtime) ---"
docker compose up -d --remove-orphans

echo "--- Remote: cleaning up old images ---"
docker image prune -f

echo "--- Remote: deploy complete ✓ ---"
docker compose ps
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  Deploy Complete!                                 ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  API:       http://$INSTANCE_IP/api"
echo "  WebSocket: ws://$INSTANCE_IP/ws"
echo "  TURN:      turn:$INSTANCE_IP:3478"
echo ""
echo "  SSH:  ssh -i $SSH_KEY ec2-user@$INSTANCE_IP"
echo "  Logs: ssh -i $SSH_KEY ec2-user@$INSTANCE_IP 'docker compose -f /opt/rpg-platform/docker-compose.yml logs -f'"
echo ""
