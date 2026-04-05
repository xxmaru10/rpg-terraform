# modules/storage/outputs.tf

output "bucket_name" {
  value = aws_s3_bucket.assets.id
}

output "bucket_arn" {
  value = aws_s3_bucket.assets.arn
}

output "bucket_regional_domain" {
  value = aws_s3_bucket.assets.bucket_regional_domain_name
}
