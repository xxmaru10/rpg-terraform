# modules/compute/outputs.tf

output "instance_id" {
  value = aws_instance.main.id
}

output "instance_public_ip" {
  value = aws_eip.main.public_ip
}

output "instance_private_ip" {
  value = aws_instance.main.private_ip
}

output "key_pair_name" {
  value = aws_key_pair.main.key_name
}
