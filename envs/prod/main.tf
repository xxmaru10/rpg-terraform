# envs/prod/main.tf
# Phase 1: Production-grade — ALB + ASG + RDS + CloudFront
# Promote from free with: terraform workspace select prod && terraform apply
# App code requires ZERO changes — only infra changes

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "rpg-platform-tfstate" # Replaced by bootstrap.sh
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "rpg-platform-tflock"
  }
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
    Environment = "prod"
    ManagedBy   = "terraform"
    Phase       = "1"
  }
}

# ──────────────────────────────────────────────
# Networking (2 AZs for HA)
# ──────────────────────────────────────────────
module "networking" {
  source = "../../modules/networking"

  project              = var.project
  env                  = "prod"
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  availability_zones   = ["${var.aws_region}a", "${var.aws_region}b"]
  ssh_allowed_cidrs    = var.ssh_allowed_cidrs
  create_rds_sg        = true
  tags                 = local.common_tags
}

# ──────────────────────────────────────────────
# Storage
# ──────────────────────────────────────────────
module "storage" {
  source = "../../modules/storage"

  project              = var.project
  env                  = "prod"
  bucket_name          = "${var.project}-prod-assets-${var.aws_account_id}"
  cors_allowed_origins = var.cors_allowed_origins
  tags                 = local.common_tags
}

# ──────────────────────────────────────────────
# RDS PostgreSQL (replaces Docker Postgres)
# db.t4g.micro: ~$15/mo, 1GB RAM — fine for <500 users
# ──────────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-prod-db-subnet"
  subnet_ids = module.networking.private_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${var.project}-prod-db-subnet"
  })
}

resource "aws_db_instance" "postgres" {
  identifier = "${var.project}-prod-postgres"

  engine               = "postgres"
  engine_version       = "16"
  instance_class       = "db.t4g.micro"  # ARM Graviton, cheapest RDS
  allocated_storage    = 20
  max_allocated_storage = 100            # Auto-scaling storage up to 100GB
  storage_type         = "gp3"
  storage_encrypted    = true

  db_name  = var.db_name
  username = var.db_user
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [module.networking.rds_security_group_id]

  # Free automated backups
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Don't delete data on terraform destroy (safety net)
  deletion_protection = true
  skip_final_snapshot = false
  final_snapshot_identifier = "${var.project}-prod-final-snapshot"

  performance_insights_enabled = false  # Saves $
  monitoring_interval          = 0      # Saves $

  tags = merge(local.common_tags, {
    Name = "${var.project}-prod-postgres"
  })
}

# ──────────────────────────────────────────────
# Application Load Balancer
# ──────────────────────────────────────────────
resource "aws_lb" "main" {
  name               = "${var.project}-prod-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.networking.ec2_security_group_id]
  subnets            = module.networking.public_subnet_ids

  tags = local.common_tags
}

resource "aws_lb_target_group" "backend" {
  name     = "${var.project}-prod-backend-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = module.networking.vpc_id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # Redirect HTTP to HTTPS in prod
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

# ──────────────────────────────────────────────
# Auto Scaling Group
# ──────────────────────────────────────────────
resource "aws_launch_template" "backend" {
  name_prefix   = "${var.project}-prod-backend-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.small"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_prod.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [module.networking.ec2_security_group_id]
  }

  user_data = base64encode(templatefile("../../modules/compute/user_data.sh.tpl", {
    project       = var.project
    env           = "prod"
    db_password   = var.db_password
    db_name       = var.db_name
    db_user       = var.db_user
    turn_secret   = var.turn_secret
    s3_bucket     = module.storage.bucket_name
    aws_region    = var.aws_region
    nest_api_port = 3000
    domain        = var.domain
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${var.project}-prod-backend"
    })
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_iam_role" "ec2_prod" {
  name = "${var.project}-prod-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_instance_profile" "ec2_prod" {
  name = "${var.project}-prod-ec2-profile"
  role = aws_iam_role.ec2_prod.name
}

resource "aws_autoscaling_group" "backend" {
  name                = "${var.project}-prod-asg"
  desired_capacity    = 1
  min_size            = 1
  max_size            = 4
  vpc_zone_identifier = module.networking.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.backend.arn]

  launch_template {
    id      = aws_launch_template.backend.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 120

  tag {
    key                 = "Name"
    value               = "${var.project}-prod-backend"
    propagate_at_launch = true
  }
}

# Scale up when CPU > 70%
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.project}-prod-scale-up"
  autoscaling_group_name = aws_autoscaling_group.backend.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# ──────────────────────────────────────────────
# Dedicated Coturn instance (TURN needs stable IP)
# ──────────────────────────────────────────────
module "coturn" {
  source = "../../modules/compute"

  project           = var.project
  env               = "prod-turn"
  aws_region        = var.aws_region
  subnet_id         = module.networking.public_subnet_ids[0]
  security_group_id = module.networking.ec2_security_group_id
  availability_zone = "${var.aws_region}a"
  instance_type     = "t4g.nano"  # ARM, ~$1.50/mo — TURN is lightweight
  ebs_size_gb       = 8
  public_key        = var.public_key
  s3_bucket_name    = module.storage.bucket_name
  db_password       = var.db_password
  db_name           = var.db_name
  db_user           = var.db_user
  turn_secret       = var.turn_secret
  domain            = var.domain
  tags              = local.common_tags
}
