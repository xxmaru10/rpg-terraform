# envs/dev/variables.tf

variable "project" {
  type    = string
  default = "rpg-platform"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_account_id" {
  type        = string
  description = "Your AWS account ID (used for unique S3 bucket name)"
}

variable "public_key" {
  type        = string
  description = "SSH public key content (paste contents of ~/.ssh/id_rsa.pub or similar)"
}

variable "ssh_allowed_cidrs" {
  type        = list(string)
  description = "Your IP address for SSH access. Get it: curl ifconfig.me"
  default     = ["0.0.0.0/0"]
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "PostgreSQL password for the dev database"
}

variable "db_name" {
  type    = string
  default = "rpgplatform_dev"
}

variable "db_user" {
  type    = string
  default = "rpgadmin"
}

variable "turn_secret" {
  type        = string
  sensitive   = true
  description = "Shared secret for Coturn TURN authentication"
}

variable "turn_realm" {
  type        = string
  description = "Realm for Coturn TURN authentication"
}

variable "domain" {
  type        = string
  default     = "cronosvtt.com"
  description = "Root domain — dev subdomains (dev-api, dev-db) are created under this"
}

variable "cors_allowed_origins" {
  type    = list(string)
  default = [
    "http://localhost:3000",
    "http://localhost:3001",
    "https://dev-api.cronosvtt.com"
  ]
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ssh_private_key_path" {
  type    = string
  default = "~/.ssh/rpg-platform"
}

variable "supabase_url" {
  type      = string
  sensitive = true
}

variable "supabase_key" {
  type      = string
  sensitive = true
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "dev_allowed_ips" {
  type    = list(string)
  default = []
}
