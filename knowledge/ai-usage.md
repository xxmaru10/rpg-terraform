---
description: Guidelines for AI agents to work efficiently and reduce token/cost usage when operating on this Terraform repository.
last_updated: 2026-05-05
---

# AI Usage Guidelines

## 1. Cost Awareness
- This is a personal/indie project — minimize unnecessary token consumption
- Prefer targeted file reads over full-repository scans
- Prefer `view_file` with line ranges over reading entire files

## 2. Terraform-Specific Efficiency
- Always read `variables.tf` before `main.tf` — variables give you the interface contract quickly
- Read `outputs.tf` to understand what a module exports before tracing usages
- Environment entrypoints (`envs/*/main.tf`) show how modules are composed — start there for "big picture" tasks
- Never read `.terraform.lock.hcl` — it's auto-generated and provides no useful context

## 3. Change Validation
- After modifying `.tf` files, run `terraform validate` to catch syntax errors
- After modifying `.sh` scripts, run `bash -n <script>` for syntax checking
- Never run `terraform apply` without user approval
- Always run `terraform plan` and present the output to the user before applying

## 4. Safe Operations
- Never modify `terraform.tfvars` — it contains real secrets
- Never modify the S3 backend config unless instructed by the user
- Never modify `bootstrap.sh` post-bootstrap (it's one-time only)
- Treat `user_data.sh.tpl` changes as high-risk — they only take effect on instance replacement
