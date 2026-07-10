###############################################################################
# Remote state backend: S3 bucket (versioned, encrypted, private).
# Locking is S3-native (use_lockfile in the eks backend) — no DynamoDB.
###############################################################################

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

###############################################################################
# GitHub Actions OIDC: provider + role CI assumes (no long-lived AWS keys)
###############################################################################

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "gha_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to this repo (any branch/PR). Tighten to specific branches/envs later.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "aria-github-actions"
  assume_role_policy = data.aws_iam_policy_document.gha_assume.json
}

# Start with read-only for CI (plan, eval inspection). Grant write/apply deliberately later
# via a separate, environment-scoped role rather than widening this one.
resource "aws_iam_role_policy_attachment" "gha_readonly" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# The "separate, environment-scoped role" mentioned above: write access for the eval
# gate specifically (push the eval-runner image, apply/watch a Job in `kagent`).
# Kept distinct from aria-github-actions so a bug in the eval workflow can't touch
# anything the read-only role wasn't already allowed to see.
resource "aws_iam_role" "github_actions_eval" {
  name               = "aria-github-actions-eval"
  assume_role_policy = data.aws_iam_policy_document.gha_assume.json
}

resource "aws_iam_role_policy_attachment" "gha_eval_ecr" {
  role       = aws_iam_role.github_actions_eval.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

# eks:DescribeCluster is required just to call `aws eks update-kubeconfig` and get a
# token - separate from the EKS access entry (infra/02-eks), which governs Kubernetes
# RBAC only *after* this IAM-level authentication succeeds. Scoped to the aria cluster.
resource "aws_iam_role_policy" "gha_eval_eks_describe" {
  name = "eks-describe-cluster"
  role = aws_iam_role.github_actions_eval.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "eks:DescribeCluster"
      Resource = "arn:aws:eks:ap-southeast-1:622629043701:cluster/aria"
    }]
  })
}
