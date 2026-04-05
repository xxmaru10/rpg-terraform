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
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  content = "216.198.79.1"
  type    = "A"
  proxied = false
  ttl     = 60
  comment = "Frontend — Vercel"
}

resource "cloudflare_record" "www" {
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
  name    = "api"
  content = var.ec2_public_ip
  type    = "A"
  proxied = true
  ttl     = 1
  comment = "Backend API — EC2"
}

resource "cloudflare_zone_settings_override" "main" {
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