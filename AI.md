---
repo: rpg-terraform
language: en
last_updated: 2026-05-07
---

# Cronos VTT — Infrastructure (Terraform)

> AWS infrastructure-as-code for the Cronos VTT RPG platform, managing networking, compute (EC2), storage (S3), DNS (Cloudflare), and operational scripts (deploy, backup, migration).

## How to use this file
This is the entry point for AI agents. Read this file first and nothing else.
Based on the sections below, load only the files relevant to your current task.
Keep the context window usage between 50% and 70%.

## Sibling Repositories
- **Frontend**: `../` (Next.js on Vercel)
- **Backend**: `../backend/` (NestJS on EC2/Docker)

## Critical Files Map (always read before any task)
| File | Purpose |
|---|---|
| `/knowledge/architecture.md` | Infrastructure architecture, modules, phases, and data flow |
| `/knowledge/conventions.md` | Terraform naming, file layout, and coding standards |
| `/knowledge/ai-usage.md` | AI efficiency and cost-reduction guide (read always) |
| `/README.md` | Human-facing project overview, quick start, and port reference |

## Load by Context (load only what's relevant)
| If your task involves... | Load these files |
|---|---|
| Networking (VPC, subnets, security groups) | `/modules/networking/main.tf`, `/modules/networking/variables.tf` |
| Compute (EC2, IAM, EBS, CloudWatch) | `/modules/compute/main.tf`, `/modules/compute/variables.tf`, `/modules/compute/user_data.sh.tpl` |
| Storage (S3 buckets, lifecycle) | `/modules/storage/main.tf`, `/modules/storage/variables.tf` |
| DNS and CDN (Cloudflare) | `/modules/cloudflare/main.tf`, `/modules/cloudflare/USAGE.md` |
| Deploying / CI-CD | `/scripts/deploy.sh`, `/scripts/bootstrap.sh` |
| Database backup and restore | `/scripts/backup.sh`, `/scripts/migrate-supabase.sh` |
| Free-tier environment setup | `/envs/free/main.tf`, `/envs/free/variables.tf`, `/envs/free/terraform.tfvars.example` |
| Dev environment setup | `/envs/dev/main.tf`, `/envs/dev/variables.tf`, `/envs/dev/terraform.tfvars.example` |
| Production environment setup | `/envs/prod/main.tf`, `/envs/prod/variables.tf` |
| Nginx / Reverse proxy config | `/modules/compute/configs/nginx.conf` |
| TURN/STUN (WebRTC) | `/modules/compute/configs/turnserver.conf` |

## Active Epics
No active epics.

## Available Tags
`terraform` `aws` `ec2` `s3` `vpc` `cloudflare` `dns` `docker` `nginx` `coturn` `webrtc` `backup` `deploy` `free-tier` `production` `stable`

## Agent Behavior Rules

### Strict Navigation Rules (CRITICAL)
1. **No blind scanning**: Do not use global `grep` or recursive `list_dir` without a specific goal based on the task. Use the Knowledge Graph (`/knowledge`) first.
2. **Loading Protocol**: Before loading the content of an `.md` file, read only the first 150 characters to validate the `description` in the YAML Front Matter. Only load the full file if it is strictly necessary.
3. **Context Limit**: Keep context window usage between **50% and 70%**. If you need to load more than 3 large files (>500 lines), **ask the human first**.
4. **Scope Focus**: Do not modify files outside the scope described in the current task. If you need to make a "cross-file" change, log the need in `AI.md` first.
5. **Reactive Update**: Upon completion, update `last_updated` and record architectural decisions in `/knowledge/architecture.md`.
