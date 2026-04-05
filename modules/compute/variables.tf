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