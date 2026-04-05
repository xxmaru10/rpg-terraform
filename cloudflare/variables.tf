# modules/cloudflare/variables.tf

variable "domain" {
  type        = string
  description = "Your root domain (e.g. crownvtt.com)"
}

variable "ec2_public_ip" {
  type        = string
  description = "EC2 Elastic IP for API subdomain"
}

variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "Cloudflare API token — create at dash.cloudflare.com/profile/api-tokens"
}
