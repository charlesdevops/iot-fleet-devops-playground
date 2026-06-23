output "dynamodb_table_name" {
  description = "Name of the DynamoDB devices table"
  value       = aws_dynamodb_table.devices.name
}

output "s3_bucket_name" {
  description = "Name of the S3 firmware bucket"
  value       = aws_s3_bucket.firmware.bucket
}

output "iam_role_arn" {
  description = "ARN of the IAM role used by the application (annotate the Kubernetes ServiceAccount with this)"
  value       = aws_iam_role.app_role.arn
}

output "s3_kms_key_arn" {
  description = "ARN of the KMS CMK used to encrypt the S3 firmware bucket"
  value       = aws_kms_key.s3.arn
}
