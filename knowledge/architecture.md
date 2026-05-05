---
description: Infrastructure architecture overview — modules, phases, data flow, and operational topology for the Cronos VTT platform on AWS.
last_updated: 2026-05-04
---

# Architecture Overview

Terraform IaC for "Cronos VTT", an online tabletop RPG platform. Two deployment phases (free-tier single EC2, production ALB+ASG+RDS). Uses modular Terraform, Cloudflare DNS, Docker Compose for the application stack, and bash scripts for operations.

## Architecture Diagram

```text
┌─────────────────────────────────────────────────────────────┐
│  PHASE 0 — FREE TIER (~$0/mo)                               │
│                                                             │
│  Vercel (free)  ──►  Next.js Frontend                       │
│                                                             │
│  Cloudflare     ──►  DNS, CDN, SSL (Flexible)               │
│                                                             │
│  AWS Free Tier                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  t3.micro EC2  (750hrs/mo free for 12 months)        │   │
│  │  ┌──────────┐ ┌──────────┐ ┌─────────┐ ┌────────┐  │   │
│  │  │ NestJS   │ │Postgres16│ │ Coturn  │ │ Nginx  │  │   │
│  │  │ :3000    │ │ :5432    │ │3478/5349│ │:80/443 │  │   │
│  │  └──────────┘ └──────────┘ └─────────┘ └────────┘  │   │
│  │  EBS gp3 20GB (mounted at /data)                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  S3 Bucket  ──►  Maps, Tokens, Audio, PDFs (5GB free)       │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  PHASE 1 — PRODUCTION (~$60-80/mo)                          │
│  (promote with: terraform workspace select prod)            │
│                                                             │
│  Vercel / CloudFront  ──►  Next.js Frontend                 │
│                                                             │
│  ALB  ──►  Auto Scaling Group (t3.small+)                   │
│            ├── NestJS containers                            │
│            └── Coturn (dedicated t4g.nano)                  │
│                                                             │
│  RDS PostgreSQL  (db.t4g.micro, ~$15/mo)                    │
│  S3 + CloudFront CDN  (assets)                              │
└─────────────────────────────────────────────────────────────┘
```

## Deployment Phases

### Phase 0 — Free Tier (~$0/mo)
- Single `t3.micro` EC2 (Amazon Linux 2023, x86_64)
- Docker Compose stack: NestJS (:3000), PostgreSQL 16 (:5432), Coturn (:3478/:5349), Nginx (:80/:443)
- EBS gp3 20GB mounted at `/data` (postgres data, uploads, coturn logs)
- S3 for game assets (maps, tokens, audio, PDFs)
- Cloudflare DNS + CDN (API proxied, frontend on Vercel)
- Terraform state in S3 + DynamoDB lock

### Phase 1 — Production (~$60–80/mo)
- ALB → Auto Scaling Group (t3.small, 1–4 instances)
- RDS PostgreSQL `db.t4g.micro` in private subnets
- Dedicated Coturn `t4g.nano` instance
- CloudFront CDN for assets
- ACM certificate for HTTPS on ALB

## Module Dependency Map

```text
envs/free/main.tf
  ├── modules/networking   (VPC, subnets, SGs, IGW)
  ├── modules/storage      (S3 bucket, lifecycle, CORS)
  ├── modules/compute      (EC2, IAM, EBS, EIP, CloudWatch, SNS)
  └── modules/cloudflare   (DNS records, zone settings)

envs/prod/main.tf
  ├── modules/networking   (2-AZ VPC, RDS SG enabled)
  ├── modules/storage      (same module, prod config)
  ├── modules/compute      (reused for dedicated Coturn instance)
  └── [inline resources]   (RDS, ALB, ASG, Launch Template)
```

## Module Reference Table

| Module | Path | Resources Created | Key Variables |
|---|---|---|---|
| networking | `modules/networking/` | VPC, public/private subnets, IGW, route tables, EC2 SG, RDS SG (conditional) | `vpc_cidr`, `public_subnet_cidrs`, `ssh_allowed_cidrs`, `create_rds_sg` |
| compute | `modules/compute/` | Key pair, IAM role/profile (S3, ECR, SSM, CloudWatch), AMI data source, EBS volume, EC2 instance, EIP, CloudWatch dashboard + alarms, SNS topic | `instance_type`, `ebs_size_gb`, `db_password`, `turn_secret`, `s3_bucket_name` |
| storage | `modules/storage/` | S3 bucket, versioning, encryption, public access block, CORS, lifecycle rules, public read policy for `uploads/*` | `bucket_name`, `cors_allowed_origins` |
| cloudflare | `modules/cloudflare/` | DNS records (root A, www A, api A proxied, db A dev, _vercel TXT), zone settings (SSL flexible, TLS 1.2+, brotli, websockets) | `domain`, `ec2_public_ip`, `cloudflare_api_token` |

## Operational Scripts

| Script | Purpose | When to Run |
|---|---|---|
| `scripts/bootstrap.sh` | One-time AWS account setup: S3 state bucket, DynamoDB lock table, ECR repos, patches backend config | Before first `terraform init` |
| `scripts/deploy.sh` | Build Docker images → push to ECR → upload configs to S3 → SSH into EC2 → pull + restart stack | After every backend code change |
| `scripts/backup.sh` | Dump PostgreSQL via `docker exec` → gzip → upload to S3 (STANDARD_IA) → prune old backups (keep 30) | Cron daily at 02:00 UTC, or manual |
| `scripts/migrate-supabase.sh` | Phase 1 of Supabase migration: dump DB → restore on EC2 Docker Postgres + sync Supabase Storage → S3 | One-time migration |

## Secrets & State Management
- Terraform state: S3 bucket `rpg-platform-tfstate-{account_id}` with DynamoDB locking
- Secrets passed via `terraform.tfvars` (git-ignored) → EC2 user_data → `/etc/rpg-platform.env`
- Sensitive variables marked with `sensitive = true` in Terraform
- EC2 IAM Instance Profile for S3/ECR/SSM/CloudWatch access (no hardcoded AWS credentials)

## Networking Topology
- VPC `10.0.0.0/16`
- Free tier: 1 AZ, 1 public subnet (`10.0.1.0/24`), 1 private subnet (`10.0.10.0/24`)
- Prod: 2 AZs, 2 public subnets, 2 private subnets
- Security groups: EC2 SG (HTTP/S, SSH restricted, STUN/TURN, Postgres dev restricted), RDS SG (Postgres from EC2 only, prod only)

## Monitoring & Alerting
- CloudWatch dashboard: CPU utilization, CPU credits, memory %, disk % on `/data`, network in/out, backend error logs
- Alarms → SNS email: CPU credits < 20 (throttle warning), disk > 80% (`/data`), instance health check failed
- Custom namespace: `RPGPlatform/EC2` for memory and disk metrics (requires CloudWatch agent)

## Key Architectural Decisions
1. **Single EC2 + Docker Compose for Phase 0** to stay within AWS free tier.
2. **Separate EBS volume for `/data`** to survive instance replacement.
3. **Cloudflare with `ssl = "flexible"`** because EC2 runs HTTP-only Nginx (Cloudflare terminates TLS).
4. **`uploads/*` in S3 is publicly readable** for direct asset serving to frontend.
5. **Coturn on a dedicated `t4g.nano` in prod** because TURN needs a stable public IP while backend scales horizontally.
