resource "aws_dynamodb_table" "devices" {
  name         = "devices-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "device_id"

  attribute {
    name = "device_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "devices-${var.environment}"
  }
}
