locals {
  using_localstack = var.localstack_endpoint != ""

  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
