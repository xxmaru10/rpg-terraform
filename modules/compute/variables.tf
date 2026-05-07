# modules/compute/variables.tf

variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "availability_zone" {
  type = string
}

variable "public_key" {
  type        = string
  description = "SSH public key content"
}

variable "s3_bucket_name" {
  type = string
}

variable "s3_backup_bucket_name" {
  type        = string
  description = "S3 bucket for PostgreSQL backups"
}

variable "db_password" {
  type      = string
  sensitive = true
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
  type      = string
  sensitive = true
}

variable "turn_realm" {
  type        = string
  description = "Realm for Coturn TURN authentication"
}

variable "domain" {
  type    = string
  default = "localhost"
}

variable "nest_api_port" {
  type    = number
  default = 3000
}

variable "instance_type" {
  type    = string
  default = "t2.micro" # Free tier eligible
}

variable "ebs_size_gb" {
  type    = number
  default = 20 # Plenty for MVP; gp3 is cheap (~$1.60/mo per 20GB)
}

variable "tags" {
  type    = map(string)
  default = {}
}


variable "ssh_private_key_path" {
  type        = string
  description = "Path to SSH private key for provisioner"
  default     = "~/.ssh/rpg-platform"
}

variable "supabase_url" {
  type      = string
  sensitive = true
}

variable "supabase_key" {
  type      = string
  sensitive = true
}

variable "use_spot" {
  type        = bool
  default     = false
  description = "Use spot instances instead of on-demand (cheaper, may be interrupted)"
}

variable "spot_max_price" {
  type        = string
  default     = ""
  description = "Maximum hourly spot price. Empty = on-demand price cap (recommended)."
}

variable "enable_backup" {
  type        = bool
  default     = true
  description = "Enable automated PostgreSQL backup timer and provisioners"
}