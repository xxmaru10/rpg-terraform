#!/usr/bin/env bash
# scripts/bootstrap.sh
# Run ONCE to set up AWS account prerequisites for Terraform
# Creates: S3 state bucket, DynamoDB lock table, ECR repos
#
# Usage: ./bootstrap.sh [--region us-east-1] [--project rpg-platform]

set -euo pipefail

# ──────────────────────────────────────────────
# Config
# ──────────────────────────────────────────────
REGION="${AWS_REGION:-us-east-1}"
PROJECT="${PROJECT:-rpg-platform}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
STATE_BUCKET="${PROJECT}-tfstate-${ACCOUNT_ID}"
LOCK_TABLE="${PROJECT}-tflock"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║     RPG Platform — AWS Bootstrap                 ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  Account ID : $ACCOUNT_ID"
echo "  Region     : $REGION"
echo "  Project    : $PROJECT"
echo "  State S3   : $STATE_BUCKET"
echo "  Lock Table : $LOCK_TABLE"
echo ""
read -p "Proceed? (y/N): " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ──────────────────────────────────────────────
# 1. Terraform state S3 bucket
# ──────────────────────────────────────────────
echo ""
echo ">>> Creating Terraform state bucket..."

if aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
  echo "    Bucket already exists: $STATE_BUCKET"
else
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket \
      --bucket "$STATE_BUCKET" \
      --region "$REGION"
  else
    aws s3api create-bucket \
      --bucket "$STATE_BUCKET" \
      --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION"
  fi
  echo "    Created: $STATE_BUCKET"
fi

# Enable versioning on state bucket
aws s3api put-bucket-versioning \
  --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket "$STATE_BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}
    }]
  }'

# Block all public access
aws s3api put-public-access-block \
  --bucket "$STATE_BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "    State bucket configured ✓"

# ──────────────────────────────────────────────
# 2. DynamoDB lock table
# ──────────────────────────────────────────────
echo ""
echo ">>> Creating DynamoDB lock table..."

if aws dynamodb describe-table --table-name "$LOCK_TABLE" --region "$REGION" 2>/dev/null; then
  echo "    Lock table already exists: $LOCK_TABLE"
else
  aws dynamodb create-table \
    --table-name "$LOCK_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"

  echo "    Waiting for table to be active..."
  aws dynamodb wait table-exists --table-name "$LOCK_TABLE" --region "$REGION"
  echo "    Lock table created ✓"
fi

# ──────────────────────────────────────────────
# 3. ECR repositories (for Docker images)
# ──────────────────────────────────────────────
echo ""
echo ">>> Creating ECR repositories..."

for repo in "rpg-backend" "rpg-nginx"; do
  FULL_REPO="${PROJECT}-${repo}"
  if aws ecr describe-repositories --repository-names "$FULL_REPO" --region "$REGION" 2>/dev/null; then
    echo "    ECR repo already exists: $FULL_REPO"
  else
    aws ecr create-repository \
      --repository-name "$FULL_REPO" \
      --region "$REGION" \
      --image-scanning-configuration scanOnPush=true \
      --encryption-configuration encryptionType=AES256

    # Lifecycle: keep only last 10 images to save storage
    aws ecr put-lifecycle-policy \
      --repository-name "$FULL_REPO" \
      --region "$REGION" \
      --lifecycle-policy-text '{
        "rules": [{
          "rulePriority": 1,
          "description": "Keep last 10 images",
          "selection": {
            "tagStatus": "any",
            "countType": "imageCountMoreThan",
            "countNumber": 10
          },
          "action": {"type": "expire"}
        }]
      }'

    echo "    Created ECR: $FULL_REPO ✓"
  fi
done

# ──────────────────────────────────────────────
# 4. Update backend.tf with real bucket name
# ──────────────────────────────────────────────
echo ""
echo ">>> Patching Terraform backend config..."

BACKEND_FILE="$(dirname "$0")/../envs/free/main.tf"
if [ -f "$BACKEND_FILE" ]; then
  sed -i.bak "s/rpg-platform-tfstate/${STATE_BUCKET}/g" "$BACKEND_FILE"
  echo "    Updated backend bucket in envs/free/main.tf ✓"
fi

BACKEND_FILE_PROD="$(dirname "$0")/../envs/prod/main.tf"
if [ -f "$BACKEND_FILE_PROD" ]; then
  sed -i.bak "s/rpg-platform-tfstate/${STATE_BUCKET}/g" "$BACKEND_FILE_PROD"
  echo "    Updated backend bucket in envs/prod/main.tf ✓"
fi

# ──────────────────────────────────────────────
# 5. Print next steps
# ──────────────────────────────────────────────
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Bootstrap Complete!                                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  State bucket : s3://$STATE_BUCKET"
echo "  Lock table   : $LOCK_TABLE"
echo "  ECR registry : $ECR_REGISTRY"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Generate SSH key (if not done):"
echo "     ssh-keygen -t ed25519 -f ~/.ssh/rpg-platform -C 'rpg-platform'"
echo ""
echo "  2. Configure tfvars:"
echo "     cd envs/free"
echo "     cp terraform.tfvars.example terraform.tfvars"
echo "     # Edit terraform.tfvars with your values"
echo "     # Set public_key to: \$(cat ~/.ssh/rpg-platform.pub)"
echo "     # Set aws_account_id to: $ACCOUNT_ID"
echo ""
echo "  3. Deploy infra:"
echo "     terraform init"
echo "     terraform plan"
echo "     terraform apply"
echo ""
echo "  4. Build and push Docker images:"
echo "     ./scripts/deploy.sh --env free"
echo ""
echo "  5. Migrate Supabase data:"
echo "     ./scripts/migrate-supabase.sh"
echo ""
