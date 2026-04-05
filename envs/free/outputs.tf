# envs/free/outputs.tf

output "instance_public_ip" {
  description = "EC2 public IP — point your DNS here, set in NEXT_PUBLIC_API_URL"
  value       = module.compute.instance_public_ip
}

output "instance_id" {
  value = module.compute.instance_id
}

output "s3_bucket_name" {
  description = "S3 bucket for game assets"
  value       = module.storage.bucket_name
}

output "api_url" {
  description = "Backend API URL to set in your Next.js NEXT_PUBLIC_API_URL env var"
  value       = "http://${module.compute.instance_public_ip}/api"
}

output "websocket_url" {
  description = "WebSocket URL for real-time (Socket.IO / WS)"
  value       = "ws://${module.compute.instance_public_ip}/ws"
}

output "turn_url" {
  description = "TURN server URL for WebRTC peer configuration"
  value       = "turn:${module.compute.instance_public_ip}:3478"
}

output "ssh_command" {
  description = "SSH into the instance"
  value       = "ssh -i ~/.ssh/your-key.pem ec2-user@${module.compute.instance_public_ip}"
}
