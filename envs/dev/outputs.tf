# envs/dev/outputs.tf

output "instance_public_ip" {
  description = "EC2 public IP (spot instance)"
  value       = module.compute.instance_public_ip
}

output "instance_id" {
  value = module.compute.instance_id
}

output "s3_bucket_name" {
  description = "S3 bucket for dev game assets"
  value       = module.storage.bucket_name
}

output "s3_backup_bucket_name" {
  description = "S3 bucket for dev PostgreSQL backups (inactive)"
  value       = module.backup_storage.bucket_name
}

output "api_url" {
  description = "Dev Backend API URL"
  value       = "https://dev-api.${var.domain}/api"
}

output "websocket_url" {
  description = "Dev WebSocket URL for real-time"
  value       = "wss://dev-api.${var.domain}/ws"
}

output "ssh_command" {
  description = "SSH into the dev instance"
  value       = "ssh -i ~/.ssh/rpg-platform ec2-user@${module.compute.instance_public_ip}"
}
