---
description: Terraform naming conventions, file structure standards, and coding patterns used in the Cronos VTT infrastructure repository.
last_updated: 2026-05-04
---

# Conventions

## 1. Repository Layout
```text
rpg-terraform/
├── AI.md                      # AI agent entry point
├── README.md                  # Human-facing documentation
├── .gitignore                 # Ignores .tfstate, .tfvars, .terraform/, keys
├── knowledge/                 # AI knowledge base
│   ├── architecture.md
│   ├── conventions.md
│   └── ai-usage.md
├── modules/                   # Reusable Terraform modules
│   ├── networking/            # VPC, subnets, security groups
│   ├── compute/               # EC2, IAM, EBS, CloudWatch
│   │   └── configs/           # nginx.conf, turnserver.conf
│   ├── storage/               # S3 buckets
│   └── cloudflare/            # DNS records, zone settings
├── envs/                      # Environment compositions
│   ├── free/                  # Phase 0: single EC2, Docker
│   └── prod/                  # Phase 1: ALB + ASG + RDS
└── scripts/                   # Operational bash scripts
    ├── bootstrap.sh
    ├── deploy.sh
    ├── backup.sh
    └── migrate-supabase.sh
```

## 2. File Naming Convention Per Module
Every Terraform module **must** have exactly these files:
- `main.tf` — resource definitions
- `variables.tf` — input variable declarations
- `outputs.tf` — output value declarations

Optional:
- `configs/` subdirectory for non-Terraform config files (nginx, coturn, etc.)
- `USAGE.md` for module usage examples (see `modules/cloudflare/USAGE.md`)

No `providers.tf` inside modules — providers are declared only in environment entrypoints (`envs/*/main.tf`).

## 3. Resource Naming Pattern
All AWS resources follow the pattern:

```text
${var.project}-${var.env}-<resource-purpose>
```

Examples from the codebase:

| Pattern | Example |
|---|---|
| Key pair | `rpgplatform-free-key` |
| IAM role | `rpgplatform-free-ec2-role` |
| EC2 instance (Name tag) | `rpgplatform-free-server` |
| EBS volume | `rpgplatform-free-data-volume` |
| Elastic IP | `rpgplatform-free-eip` |
| VPC | `rpgplatform-free-vpc` |
| Subnet (public) | `rpgplatform-free-public-1` |
| Security group | `rpgplatform-free-ec2-sg` |
| S3 bucket | `rpgplatform-free-assets-{account_id}` |
| RDS (prod) | `rpgplatform-prod-postgres` |
| ALB (prod) | `rpgplatform-prod-alb` |

## 4. Tagging Convention
All resources inherit `default_tags` from the AWS provider plus module-level `var.tags`:

```hcl
locals {
  common_tags = {
    Project     = var.project        # e.g., "rpgplatform"
    Environment = "free"             # "free" or "prod"
    ManagedBy   = "terraform"        # Always "terraform"
    Phase       = "0"               # "0" for free, "1" for prod
  }
}
```

Additional per-resource tags use `merge(var.tags, { Name = "..." })`.

## 5. Variable Declaration Standards
- Always include `type`
- Include `description` for non-obvious variables
- Include `default` when a sensible default exists
- Mark secrets with `sensitive = true`
- Compact one-liner format acceptable for simple variables in environment files (see `envs/prod/variables.tf`)
- Full multi-line format preferred in module definitions (see `modules/networking/variables.tf`)

## 6. Environment Composition Pattern
Environments in `envs/*/main.tf` follow this structure:
1. `terraform {}` block — version constraints, required providers, S3 backend
2. `provider` blocks — AWS region, Cloudflare token, default tags
3. `locals {}` — common tags
4. `module` blocks — compose modules with environment-specific values
5. Inline resources (prod only) — for resources not yet modularized (RDS, ALB, ASG)

## 7. Script Conventions
- Shebang: `#!/usr/bin/env bash`
- Always start with `set -euo pipefail`
- Environment defaults from variables: `ENV="${DEPLOY_ENV:-free}"`
- Scripts resolve paths relative to `SCRIPT_DIR`: `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`
- Use heredocs for multi-line remote commands over SSH
- Confirmation prompt for destructive operations: `read -p "Proceed? (y/N): " confirm`

## 8. Security Conventions
- SSH access restricted by CIDR in `ssh_allowed_cidrs` (default `0.0.0.0/0` must be overridden in tfvars)
- Postgres dev access restricted by `dev_allowed_ips` on non-standard port `5433`
- S3 state bucket: versioning, encryption, all public access blocked
- EC2 env file: `chmod 600 /etc/rpg-platform.env`
- Never commit: `.tfvars`, `.tfstate`, SSH keys, `.env` files (enforced by `.gitignore`)

## 9. When to Create a New Module vs. Inline Resources
- **Create a module** when the resource group will be reused across environments (e.g., `networking`, `storage`, `compute`)
- **Use inline resources** in `envs/*/main.tf` when the resource is environment-specific and not reusable (e.g., RDS in prod, ALB, ASG)
- The `compute` module is intentionally reused for the dedicated Coturn instance in prod (`env = "prod-turn"`)
