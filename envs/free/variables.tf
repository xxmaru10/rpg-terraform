# envs/free/variables.tf

variable "project" {
  type    = string
  default = "rpgplatform"
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
  default     = ["0.0.0.0/0"] # REPLACE with your IP/32 for security
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "PostgreSQL password — use a strong random string"
}

variable "db_name" {
  type    = string
  default = "rpgplatform"
}

variable "db_user" {
  type    = string
  default = "rpgadmin"
}

variable "turn_secret" {
  type        = string
  sensitive   = true
  description = "Shared secret for Coturn TURN authentication — random string"
}

variable "domain" {
  type        = string
  default     = "localhost"
  description = "Domain for SSL cert and TURN realm. Use EC2 public IP initially."
}

variable "cors_allowed_origins" {
  type    = list(string)
  default = ["https://*.vercel.app", "http://localhost:3000", "http://localhost:3001"]
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