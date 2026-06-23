variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g. local, dev, prod)"
  type        = string
  default     = "dev"
}

variable "localstack_endpoint" {
  description = "LocalStack endpoint URL. Set to http://localhost:4566 for local dev; leave empty for real AWS."
  type        = string
  default     = ""
}

# IRSA (IAM Roles for Service Accounts) — only needed when deploying to EKS.
# Leave empty to fall back to an EC2 trust policy (useful for testing outside EKS).
variable "eks_oidc_provider_arn" {
  description = "ARN of the EKS cluster OIDC provider"
  type        = string
  default     = ""
}

variable "eks_oidc_provider_url" {
  description = "URL of the EKS cluster OIDC provider (without https://)"
  type        = string
  default     = ""
}

variable "k8s_namespace" {
  description = "Kubernetes namespace that will use the IAM role"
  type        = string
  default     = "default"
}

variable "k8s_service_account_name" {
  description = "Kubernetes ServiceAccount name that will use the IAM role"
  type        = string
  default     = "fleet-api"
}
