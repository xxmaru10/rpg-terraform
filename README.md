# RPG Platform — AWS Infrastructure (Terraform)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  PHASE 0 — FREE TIER (~$0/mo)                               │
│                                                             │
│  Vercel (free)  ──►  Next.js Frontend                       │
│                                                             │
│  AWS Free Tier                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  t2.micro EC2  (750hrs/mo free for 12 months)        │   │
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
│            └── Coturn (dedicated t3.micro)                  │
│                                                             │
│  RDS PostgreSQL  (db.t4g.micro, ~$15/mo)                    │
│  S3 + CloudFront CDN  (assets)                              │
└─────────────────────────────────────────────────────────────┘
```

## Repository Structure

```
infra/
├── modules/
│   ├── networking/     # VPC, subnets, security groups, IGW
│   ├── compute/        # EC2 instance + key pair + EBS
│   ├── database/       # Docker PG config (free) or RDS (prod)
│   ├── storage/        # S3 bucket + IAM policies
│   └── coturn/         # TURN/STUN server config
├── envs/
│   ├── free/           # Phase 0: single t2.micro, Docker Compose
│   └── prod/           # Phase 1: ALB + ASG + RDS
├── scripts/
│   ├── bootstrap.sh          # One-time AWS account setup
│   ├── deploy.sh             # Deploy/update EC2 Docker stack
│   ├── migrate-supabase.sh   # Migrate DB + storage from Supabase
│   └── backup.sh             # Manual DB backup to S3
└── docker/
    ├── docker-compose.yml    # Full stack on EC2
    ├── nginx/
    │   └── nginx.conf
    └── coturn/
        └── turnserver.conf
```

## Quick Start

### Prerequisites
- AWS CLI configured (`aws configure`)
- Terraform >= 1.6
- Your AWS account ID handy

### 1. Bootstrap (one-time)
```bash
cd infra/scripts
chmod +x bootstrap.sh
./bootstrap.sh
```

### 2. Deploy Free Tier
```bash
cd infra/envs/free
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform workspace new free
terraform plan
terraform apply
```

### 3. Migrate from Supabase
```bash
cd infra/scripts
./migrate-supabase.sh \
  --supabase-url "https://yourproject.supabase.co" \
  --supabase-key "your-service-role-key" \
  --ec2-ip "$(terraform -chdir=../envs/free output -raw instance_public_ip)"
```

### 4. Promote to Production (when ready)
```bash
cd infra/envs/prod
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform workspace new prod
terraform plan
terraform apply
```

## Port Reference

| Service   | Port      | Protocol | Notes                          |
|-----------|-----------|----------|-------------------------------|
| Nginx     | 80, 443   | TCP      | HTTP/HTTPS, reverse proxy      |
| NestJS    | 3000      | TCP      | Internal only (via Nginx)      |
| Postgres  | 5432      | TCP      | Internal only                  |
| STUN      | 3478      | UDP/TCP  | WebRTC NAT traversal           |
| TURN      | 5349      | UDP/TCP  | WebRTC relay (TLS)             |
| TURN range| 49152-65535| UDP    | WebRTC media relay ports       |

## Environment Variables

All secrets are passed via EC2 user data and stored in `/etc/rpg-platform.env` on the instance.
Never commit `.tfvars` files containing real secrets.
