# envs/free/main.tf
# Phase 0: Single t2.micro, Docker Compose, free tier

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


  # Remote state in S3 (bucket created by bootstrap.sh)
  backend "s3" {
    bucket         = "rpg-platform-tfstate-306337361114" # Will be set by bootstrap.sh
    key            = "free/terraform.tfstate"
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
    Environment = "free"
    ManagedBy   = "terraform"
    Phase       = "0"
  }
}

# ──────────────────────────────────────────────
# Networking
# ──────────────────────────────────────────────
module "networking" {
  source = "../../modules/networking"

  project              = var.project
  env                  = "free"
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24"]
  availability_zones   = ["${var.aws_region}a"]
  ssh_allowed_cidrs    = var.ssh_allowed_cidrs
  create_rds_sg        = false
  tags                 = local.common_tags
}

# ──────────────────────────────────────────────
# Storage (S3 — free tier: 5GB, 20k GETs)
# ──────────────────────────────────────────────
module "storage" {
  source = "../../modules/storage"

  project              = var.project
  env                  = "free"
  bucket_name          = "${var.project}-free-assets-${var.aws_account_id}"
  cors_allowed_origins = var.cors_allowed_origins
  tags                 = local.common_tags
}

# ──────────────────────────────────────────────
# Compute (t2.micro — free tier eligible)
# ──────────────────────────────────────────────
module "compute" {
  source = "../../modules/compute"

  project           = var.project
  env               = "free"
  aws_region        = var.aws_region
  subnet_id         = module.networking.public_subnet_ids[0]
  security_group_id = module.networking.ec2_security_group_id
  availability_zone = "${var.aws_region}a"
  instance_type     = var.instance_type
  ebs_size_gb       = 20
  public_key        = var.public_key
  s3_bucket_name    = module.storage.bucket_name
  db_password       = var.db_password
  db_name           = var.db_name
  db_user           = var.db_user
  turn_secret       = var.turn_secret
  domain            = var.domain
  nest_api_port     = 3000
  tags              = local.common_tags
  supabase_url      = var.supabase_url
  supabase_key      = var.supabase_key
}


module "cloudflare" {
  source               = "../../modules/cloudflare"
  domain               = var.domain
  ec2_public_ip        = module.compute.instance_public_ip
  cloudflare_api_token = var.cloudflare_api_token
}
