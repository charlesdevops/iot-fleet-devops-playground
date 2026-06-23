resource "aws_kms_key" "s3" {
  description             = "CMK for S3 firmware bucket encryption - ${var.environment}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "fleet-api-s3-cmk-${var.environment}"
  }
}

resource "aws_kms_alias" "s3" {
  name          = "alias/fleet-api-s3-${var.environment}"
  target_key_id = aws_kms_key.s3.key_id
}
