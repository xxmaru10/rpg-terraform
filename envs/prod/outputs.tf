# envs/prod/outputs.tf

output "alb_dns_name" {
  description = "Point your domain CNAME to this ALB DNS name"
  value       = aws_lb.main.dns_name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (private — only accessible from EC2)"
  value       = aws_db_instance.postgres.endpoint
  sensitive   = true
}

output "turn_server_ip" {
  description = "Dedicated TURN server public IP"
  value       = module.coturn.instance_public_ip
}

output "s3_bucket" {
  value = module.storage.bucket_name
}
