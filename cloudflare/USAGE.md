# Add this to envs/free/main.tf — Cloudflare module block

# ──────────────────────────────────────────────
# Cloudflare DNS + CDN + SSL
# ──────────────────────────────────────────────
module "cloudflare" {
  source = "../../modules/cloudflare"

  domain               = var.domain
  ec2_public_ip        = module.compute.instance_public_ip
  cloudflare_api_token = var.cloudflare_api_token
}
