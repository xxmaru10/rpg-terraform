# envs/prod/variables.tf

variable "project"          { type = string; default = "rpg-platform" }
variable "aws_region"       { type = string; default = "us-east-1" }
variable "aws_account_id"   { type = string }
variable "public_key"       { type = string }
variable "ssh_allowed_cidrs"{ type = list(string) }
variable "db_password"      { type = string; sensitive = true }
variable "db_name"          { type = string; default = "rpgplatform" }
variable "db_user"          { type = string; default = "rpgadmin" }
variable "turn_secret"      { type = string; sensitive = true }
variable "domain"           { type = string }
variable "acm_certificate_arn" { type = string; description = "ACM cert ARN for HTTPS on ALB" }
variable "cors_allowed_origins" { type = list(string) }
