# modules/cloudflare/main.tf
# Manages DNS, SSL, caching and WAF rules via Cloudflare
# Free plan covers everything needed for Phase 0/1

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

# ──────────────────────────────────────────────
# Zone (your domain)
# ──────────────────────────────────────────────
data "cloudflare_zone" "main" {
  name = var.domain
}

# ──────────────────────────────────────────────
# DNS Records
# ──────────────────────────────────────────────

# Root domain → Vercel frontend
resource "cloudflare_record" "root" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  content = "cname.vercel-dns.com"
  type    = "CNAME"
  proxied = true  # Traffic goes through Cloudflare edge
  ttl     = 1     # Auto when proxied

  comment = "Frontend — Vercel"
}

# www → Vercel frontend
resource "cloudflare_record" "www" {
  zone_id = data.cloudflare_zone.main.id
  name    = "www"
  content = "cname.vercel-dns.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1

  comment = "Frontend www — Vercel"
}

# api subdomain → EC2 backend
resource "cloudflare_record" "api" {
  zone_id = data.cloudflare_zone.main.id
  name    = "api"
  content = var.ec2_public_ip
  type    = "A"
  proxied = true  # Cloudflare proxies — hides real EC2 IP
  ttl     = 1

  comment = "Backend API — EC2 ${var.ec2_public_ip}"
}

# ──────────────────────────────────────────────
# SSL/TLS — Full strict (EC2 has valid cert)
# ──────────────────────────────────────────────
resource "cloudflare_zone_settings_override" "main" {
  zone_id = data.cloudflare_zone.main.id

  settings {
    ssl                      = "full"        # Encrypt all the way to EC2
    always_use_https         = "on"          # Force HTTPS everywhere
    min_tls_version          = "1.2"
    tls_1_3                  = "zrt"
    automatic_https_rewrites = "on"
    http3                    = "on"          # HTTP/3 for performance
    brotli                   = "on"          # Better compression than gzip
    browser_cache_ttl        = 14400         # 4 hours browser cache
    cache_level              = "aggressive"
    minify {
      css  = "on"
      js   = "on"
      html = "on"
    }
    security_level = "medium"
    websockets     = "on"  # Required for real-time game sessions
  }
}

# ──────────────────────────────────────────────
# Cache Rules — cache static API responses at edge
# Reduces hits to EC2 for read-heavy endpoints
# ──────────────────────────────────────────────

# Cache bestiary (monsters — rarely changes)
resource "cloudflare_ruleset" "cache_rules" {
  zone_id = data.cloudflare_zone.main.id
  name    = "Cache rules"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules {
    action = "set_cache_settings"
    action_parameters {
      cache = true
      edge_ttl {
        mode    = "override_origin"
        default = 300  # 5 minutes at edge
      }
      browser_ttl {
        mode    = "override_origin"
        default = 60
      }
    }
    expression  = "(http.request.uri.path matches \"^/api/bestiary\") and (http.request.method eq \"GET\")"
    description = "Cache bestiary GET requests"
    enabled     = true
  }

  rules {
    action = "set_cache_settings"
    action_parameters {
      cache = true
      edge_ttl {
        mode    = "override_origin"
        default = 60  # 1 minute for sessions list
      }
      browser_ttl {
        mode    = "override_origin"
        default = 30
      }
    }
    expression  = "(http.request.uri.path matches \"^/api/sessions$\") and (http.request.method eq \"GET\")"
    description = "Cache sessions list"
    enabled     = true
  }

  rules {
    action = "set_cache_settings"
    action_parameters {
      cache = false  # Never cache real-time events
    }
    expression  = "http.request.uri.path matches \"^/api/events/\""
    description = "Bypass cache for SSE/real-time events"
    enabled     = true
  }

  rules {
    action = "set_cache_settings"
    action_parameters {
      cache = false  # Never cache WebSocket upgrades
    }
    expression  = "http.request.uri.path matches \"^/ws/\""
    description = "Bypass cache for WebSocket"
    enabled     = true
  }
}

# ──────────────────────────────────────────────
# Firewall / WAF Rules
# ──────────────────────────────────────────────
resource "cloudflare_ruleset" "firewall" {
  zone_id = data.cloudflare_zone.main.id
  name    = "Firewall rules"
  kind    = "zone"
  phase   = "http_request_firewall_custom"

  # Block common attack patterns
  rules {
    action      = "block"
    expression  = "(http.request.uri.path contains \"../\") or (http.request.uri.path contains \"..\\\\\")"
    description = "Block path traversal"
    enabled     = true
  }

  # Rate limit on API (basic protection)
  rules {
    action      = "block"
    expression  = "(http.request.uri.path matches \"^/api/\") and (cf.threat_score gt 30)"
    description = "Block high threat score requests to API"
    enabled     = true
  }
}

# ──────────────────────────────────────────────
# Page Rules — redirect www to apex
# ──────────────────────────────────────────────
resource "cloudflare_page_rule" "www_redirect" {
  zone_id  = data.cloudflare_zone.main.id
  target   = "www.${var.domain}/*"
  priority = 1

  actions {
    forwarding_url {
      url         = "https://${var.domain}/$1"
      status_code = 301
    }
  }
}
