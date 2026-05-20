# envs/dev/main.tf
# Development environment: Spot EC2, Docker Compose, dev database
# Mirrors free tier architecture but optimized for cost via spot instances

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }

  # Remote state in S3 (separate key from free/prod)
  backend "s3" {
    bucket         = "rpg-platform-tfstate-306337361114"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "rpg-platform-tflock"
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project     = var.project
    Environment = "dev"
    ManagedBy   = "terraform"
    Phase       = "dev"
  }
}

# ──────────────────────────────────────────────
# Networking (separate VPC from free)
# ──────────────────────────────────────────────
module "networking" {
  source = "../../modules/networking"

  project              = var.project
  env                  = "dev"
  vpc_cidr             = "10.1.0.0/16"
  public_subnet_cidrs  = ["10.1.1.0/24"]
  private_subnet_cidrs = ["10.1.10.0/24"]
  availability_zones   = ["${var.aws_region}a"]
  ssh_allowed_cidrs    = var.ssh_allowed_cidrs
  create_rds_sg        = false
  tags                 = local.common_tags
  dev_allowed_ips      = var.dev_allowed_ips
}

# ──────────────────────────────────────────────
# Storage (S3 — dev assets, isolated from free)
# ──────────────────────────────────────────────
module "storage" {
  source = "../../modules/storage"

  project              = var.project
  env                  = "dev"
  bucket_name          = "${var.project}-dev-assets-${var.aws_account_id}"
  cors_allowed_origins = var.cors_allowed_origins
  tags                 = local.common_tags
}

# ──────────────────────────────────────────────
# Backup Storage (S3 — exists for IAM compatibility, no timer runs)
# ──────────────────────────────────────────────
module "backup_storage" {
  source = "../../modules/backup_storage"

  project     = var.project
  env         = "dev"
  bucket_name = "${var.project}-dev-postgres-backups-${var.aws_account_id}"
  tags        = local.common_tags
}

# ──────────────────────────────────────────────
# Compute (Spot instance — dev, no backup timer)
# ──────────────────────────────────────────────
module "compute" {
  source = "../../modules/compute"

  project           = var.project
  env               = "dev"
  aws_region        = var.aws_region
  subnet_id         = module.networking.public_subnet_ids[0]
  security_group_id = module.networking.ec2_security_group_id
  availability_zone = "${var.aws_region}a"
  instance_type     = var.instance_type
  ebs_size_gb       = 10
  public_key        = var.public_key
  s3_bucket_name          = module.storage.bucket_name
  s3_backup_bucket_name   = module.backup_storage.bucket_name
  free_backup_bucket_name = var.free_backup_bucket_name
  db_password       = var.db_password
  db_name           = var.db_name
  db_user           = var.db_user
  turn_secret       = var.turn_secret
  turn_realm        = var.turn_realm
  domain            = var.domain
  nest_api_port     = 3000
  tags              = local.common_tags
  supabase_url      = var.supabase_url
  supabase_key      = var.supabase_key

  # Dev-specific: spot instance, no backups
  use_spot              = true
  enable_backup         = false
  ssh_private_key_path  = var.ssh_private_key_path
}

# ──────────────────────────────────────────────
# Cloudflare (dev-api + dev-db subdomains only)
# ──────────────────────────────────────────────
module "cloudflare" {
  source               = "../../modules/cloudflare"
  domain               = var.domain
  ec2_public_ip        = module.compute.instance_public_ip
  cloudflare_api_token = var.cloudflare_api_token

  # Dev-specific: only create dev-api and dev-db, skip frontend records and zone settings
  subdomain_prefix        = "dev-"
  create_frontend_records = false
  manage_zone_settings    = false
}
