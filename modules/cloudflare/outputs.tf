# modules/cloudflare/outputs.tf

output "frontend_url" {
  value = "https://${var.domain}"
}

output "api_url" {
  value = "https://api.${var.domain}/api"
}

output "zone_id" {
  value = data.cloudflare_zone.main.id
}
