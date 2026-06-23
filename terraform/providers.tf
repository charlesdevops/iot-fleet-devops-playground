terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }

  # Fake credentials for LocalStack (it accepts any non-empty value)
  access_key = local.using_localstack ? "test" : null
  secret_key = local.using_localstack ? "test" : null

  skip_credentials_validation = local.using_localstack
  skip_requesting_account_id  = local.using_localstack
  skip_metadata_api_check     = local.using_localstack
  s3_use_path_style           = local.using_localstack

  dynamic "endpoints" {
    for_each = local.using_localstack ? [1] : []
    content {
      dynamodb = var.localstack_endpoint
      s3       = var.localstack_endpoint
      iam      = var.localstack_endpoint
      sts      = var.localstack_endpoint
      kms      = var.localstack_endpoint
    }
  }
}
