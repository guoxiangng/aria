###############################################################################
# External Secrets Operator (ESO) backing store: AWS Secrets Manager + the IAM
# identity ESO uses to read it (EKS Pod Identity — no static keys, same pattern
# as the Bedrock / EBS-CSI roles in infra/02-eks).
#
# WHY: moves the kagent secret *material* out of git AND out of Terraform state's
# long-term ownership into Secrets Manager (the source of truth), so the in-cluster
# Secret becomes a git-committable `ExternalSecret` pointer (no secret material) that
# ArgoCD owns. See platform/external-secrets/ + agents-of-record ExternalSecrets.
#
# NOTE on seeding: Terraform seeds the initial value here from the same gitignored
# tfvars vars that currently feed the k8s Secret — so the value passes through TF
# state once during seeding (it already does today, via kubernetes_secret). After
# cutover, Secrets Manager is the source of truth and rotation happens there;
# `ignore_changes` keeps TF from clobbering a rotated value.
###############################################################################

locals {
  sm_prefix = "aria" # Secrets Manager path prefix for this platform
}

# --- Secrets Manager: the two secrets, seeded from existing tfvars vars ---

resource "aws_secretsmanager_secret" "kagent_azure" {
  name        = "${local.sm_prefix}/kagent-azure-openai"
  description = "Azure OpenAI API key for kagent agents (consumed via ESO ExternalSecret)."
}

resource "aws_secretsmanager_secret_version" "kagent_azure" {
  secret_id = aws_secretsmanager_secret.kagent_azure.id
  # JSON with keys matching the k8s Secret's keys — ESO extracts by property.
  secret_string = jsonencode({
    AZUREOPENAI_API_KEY = var.azure_openai_api_key
  })
  lifecycle {
    ignore_changes = [secret_string] # SM is source of truth post-seed; rotate there, don't let TF revert
  }
}

# Embedding credential — separate from the chat key above. kagent Memory vectorizes stored
# facts through a ModelConfig backed by an embedding deployment (text-embedding-3-large),
# which carries its own API key on the same Azure resource.
resource "aws_secretsmanager_secret" "kagent_azure_embedding" {
  name        = "${local.sm_prefix}/kagent-azure-embedding"
  description = "Azure OpenAI EMBEDDING API key for kagent Memory vectorization (consumed via ESO ExternalSecret)."
}

# NOTE the deliberate difference from the two secrets above: no `aws_secretsmanager_secret_version`
# seeded from a tfvars variable. Terraform creates the *container* only; the value is written
# out-of-band with the CLI:
#
#   aws secretsmanager put-secret-value --secret-id aria/kagent-azure-embedding \
#     --secret-string '{"AZUREOPENAI_EMBEDDING_API_KEY":"<key>"}'
#
# This keeps the credential out of tfvars AND out of Terraform state entirely (the older two still
# pass through state once at seed time). Secrets Manager is the source of truth either way; ESO reads
# it via Pod Identity. Prefer this pattern for any new secret.

# GitHub PAT for the self-hosted github-mcp-server (platform/mcp/github/). Genuinely different
# from every other secret here: it's a STATIC bearer token, not a federated cloud identity like
# EKS Pod Identity — GitHub's own MCP server (unlike the AWS ones) has no equivalent to
# "assume a role with no credential to leak." The container-only pattern applies here too, and
# matters MORE than usual: this value must never pass through tfvars or state at all. Seed with:
#
#   aws secretsmanager put-secret-value --secret-id aria/github-pat \
#     --secret-string '{"GITHUB_PERSONAL_ACCESS_TOKEN":"<fine-grained PAT, read-only, aria repo only>"}'
resource "aws_secretsmanager_secret" "github_pat" {
  name        = "${local.sm_prefix}/github-pat"
  description = "Fine-grained GitHub PAT (read-only, aria repo scope) for the self-hosted github-mcp-server."
}

resource "aws_secretsmanager_secret" "kagent_langfuse_otel" {
  name        = "${local.sm_prefix}/kagent-langfuse-otel"
  description = "Langfuse OTLP Basic-Auth header for kagent tracing (consumed via ESO ExternalSecret)."
}

resource "aws_secretsmanager_secret_version" "kagent_langfuse_otel" {
  secret_id = aws_secretsmanager_secret.kagent_langfuse_otel.id
  secret_string = jsonencode({
    OTEL_EXPORTER_OTLP_HEADERS = "Authorization=Basic ${base64encode("${var.langfuse_public_key}:${var.langfuse_secret_key}")},x-langfuse-ingestion-version=4"
  })
  lifecycle {
    ignore_changes = [secret_string]
  }
}

# --- IAM: the role ESO's ServiceAccount assumes via EKS Pod Identity ---

data "aws_iam_policy_document" "eso_pod_identity_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole", "sts:TagSession"]
  }
}

resource "aws_iam_role" "eso" {
  name               = "${var.cluster_name}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.eso_pod_identity_trust.json
}

# Least-privilege: read ONLY the secrets above (not all of Secrets Manager). Every new
# ExternalSecret needs its backing secret's ARN added here, or ESO gets AccessDenied.
data "aws_iam_policy_document" "eso_read" {
  statement {
    sid     = "ReadKagentSecrets"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [
      aws_secretsmanager_secret.kagent_azure.arn,
      aws_secretsmanager_secret.kagent_azure_embedding.arn,
      aws_secretsmanager_secret.kagent_langfuse_otel.arn,
      aws_secretsmanager_secret.github_pat.arn,
    ]
  }
}

resource "aws_iam_role_policy" "eso_read" {
  name   = "read-kagent-secrets"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso_read.json
}

# --- Pod Identity: bind ESO's controller ServiceAccount to the role ---
# The SA (external-secrets/external-secrets) is created later by the ArgoCD-managed
# ESO install; the association binds by name and does not require the SA to exist yet.
# With Pod Identity, NO annotation on the SA is needed (unlike IRSA) and the
# ClusterSecretStore needs no auth block — the AWS SDK picks creds up automatically.
resource "aws_eks_pod_identity_association" "eso" {
  cluster_name    = var.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.eso.arn
}

output "eso_role_arn" {
  description = "IAM role ESO assumes via Pod Identity to read Secrets Manager."
  value       = aws_iam_role.eso.arn
}
