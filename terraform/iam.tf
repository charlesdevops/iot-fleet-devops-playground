locals {
  using_irsa = var.eks_oidc_provider_arn != "" && var.eks_oidc_provider_url != ""

  # IRSA trust policy — allows the Kubernetes ServiceAccount to assume the role via OIDC
  irsa_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.eks_oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.eks_oidc_provider_url}:sub" = "system:serviceaccount:${var.k8s_namespace}:${var.k8s_service_account_name}"
          "${var.eks_oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  # Fallback trust policy — used for local/CI testing without a EKS OIDC provider
  ec2_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# Least-privilege policy: only the exact actions the app needs
data "aws_iam_policy_document" "app_permissions" {
  statement {
    sid = "DynamoDBAccess"
    actions = [
      "dynamodb:Scan",
      "dynamodb:PutItem",
      "dynamodb:GetItem",
    ]
    resources = [aws_dynamodb_table.devices.arn]
  }

  statement {
    sid = "S3FirmwareAccess"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
    ]
    resources = ["${aws_s3_bucket.firmware.arn}/*"]
  }

  # SSE-KMS: S3 calls KMS on behalf of the caller — the caller's identity must
  # be allowed by the key policy, so these permissions are required.
  statement {
    sid = "KMSForS3"
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
    ]
    resources = [aws_kms_key.s3.arn]
  }
}

resource "aws_iam_policy" "app_policy" {
  name        = "fleet-api-policy-${var.environment}"
  description = "Least-privilege policy for the Fleet Registry API (DynamoDB + S3)"
  policy      = data.aws_iam_policy_document.app_permissions.json

  tags = {
    Name = "fleet-api-policy-${var.environment}"
  }
}

resource "aws_iam_role" "app_role" {
  name = "fleet-api-role-${var.environment}"

  # Use IRSA trust when EKS OIDC provider is provided; EC2 trust otherwise
  assume_role_policy = local.using_irsa ? local.irsa_trust_policy : local.ec2_trust_policy

  tags = {
    Name = "fleet-api-role-${var.environment}"
  }
}

resource "aws_iam_role_policy_attachment" "app" {
  role       = aws_iam_role.app_role.name
  policy_arn = aws_iam_policy.app_policy.arn
}
