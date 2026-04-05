# modules/storage/variables.tf

variable "project" { type = string }
variable "env"     { type = string }

variable "bucket_name" {
  type        = string
  description = "Must be globally unique. Convention: {project}-{env}-assets-{account_id}"
}

variable "cors_allowed_origins" {
  type    = list(string)
  default = ["*"] # Lock this down to your Vercel domain in prod
}

variable "tags" {
  type    = map(string)
  default = {}
}
