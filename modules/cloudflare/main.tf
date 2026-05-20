terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

data "cloudflare_zone" "main" {
  name = var.domain
}

resource "cloudflare_record" "root" {
  count   = var.create_frontend_records ? 1 : 0
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  content = "216.198.79.1"
  type    = "A"
  proxied = false
  ttl     = 60
  comment = "Frontend — Vercel"
}

resource "cloudflare_record" "domainverify" {
  count   = var.create_frontend_records ? 1 : 0
  zone_id = data.cloudflare_zone.main.id
  name    = "_vercel"
  content = "vc-domain-verify=cronosvtt.com,96dfad16aa5eb2ffbcd5,dc"
  type    = "TXT"
  proxied = false
  ttl     = 600
  comment = "Vercel Domain verify"
}

resource "cloudflare_record" "www" {
  count   = var.create_frontend_records ? 1 : 0
  zone_id = data.cloudflare_zone.main.id
  name    = "www"
  content = "216.198.79.1"
  type    = "A"
  proxied = false
  ttl     = 60
  comment = "Frontend www — Vercel"
}

resource "cloudflare_record" "api" {
  zone_id = data.cloudflare_zone.main.id
  name    = "${var.subdomain_prefix}api"
  content = var.ec2_public_ip
  type    = "A"
  proxied = true
  ttl     = 1
  comment = "${var.subdomain_prefix != "" ? "Dev " : ""}Backend API — EC2"
}

resource "cloudflare_zone_settings_override" "main" {
  count   = var.manage_zone_settings ? 1 : 0
  zone_id = data.cloudflare_zone.main.id

  settings {
    ssl                      = "flexible"
    always_use_https         = "on"
    min_tls_version          = "1.2"
    tls_1_3                  = "zrt"
    automatic_https_rewrites = "on"
    brotli                   = "on"
    websockets               = "on"
    browser_cache_ttl        = 14400
    security_level           = "essentially_off" 
  }
}

resource "cloudflare_record" "db_dev" {
  zone_id = data.cloudflare_zone.main.id
  name    = "${var.subdomain_prefix}db"
  content = var.ec2_public_ip
  type    = "A"
  proxied = false 
  ttl     = 60
  comment = "${var.subdomain_prefix != "" ? "Dev env " : "Dev "}Postgres — direct connection"
}