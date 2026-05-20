# modules/backup_storage/variables.tf

variable "project" { type = string }
variable "env"     { type = string }

variable "bucket_name" {
  type        = string
  description = "Must be globally unique. Convention: {project}-postgres-backups-{account_id}"
}

variable "tags" {
  type    = map(string)
  default = {}
}
