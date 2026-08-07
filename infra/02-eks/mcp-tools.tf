###############################################################################
# IAM for self-hosted MCP tool servers (EKS Pod Identity — no static AWS keys)
#
# First increment: awslabs.aws-pricing-mcp-server, run via kmcp (see
# platform/mcp/aws-pricing/). kmcp auto-creates a ServiceAccount NAMED AFTER
# the MCPServer resource (confirmed in kmcp's controller source,
# transportadapter_translator.go: ObjectMeta.Name = server.Name) — the same
# per-resource-SA convention kagent itself uses for Agents. So the MCPServer
# named "aws-pricing" gets SA "aws-pricing" in the "kagent" namespace, and
# Pod Identity binds to that exact (namespace, name) pair, mirroring the
# existing bedrock/ebs_csi pattern below rather than inventing a new one.
#
# Reuses `data.aws_iam_policy_document.pod_identity_trust` already defined
# in main.tf (same pods.eks.amazonaws.com trust policy every Pod Identity
# role in this cluster uses).
###############################################################################

data "aws_iam_policy_document" "aws_pricing_mcp" {
  statement {
    sid    = "PricingReadOnly"
    effect = "Allow"
    # AWS Pricing API is read-only and free; the upstream server's own docs
    # (awslabs/mcp, aws-pricing-mcp-server README) state the IAM requirement
    # simply as "pricing:*" — no finer-grained action list is published.
    actions   = ["pricing:*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "aws_pricing_mcp" {
  name   = "${local.cluster_name}-mcp-aws-pricing"
  policy = data.aws_iam_policy_document.aws_pricing_mcp.json
}

resource "aws_iam_role" "aws_pricing_mcp" {
  name               = "${local.cluster_name}-mcp-aws-pricing"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "aws_pricing_mcp" {
  role       = aws_iam_role.aws_pricing_mcp.name
  policy_arn = aws_iam_policy.aws_pricing_mcp.arn
}

# The MCPServer CR (platform/mcp/aws-pricing/mcpserver.yaml) must be deployed
# BEFORE this apply can succeed — kmcp only creates the ServiceAccount once
# the MCPServer resource is reconciled. Same ordering constraint as the
# Bedrock/agent Pod Identity work: deploy first, bind identity second.
resource "aws_eks_pod_identity_association" "aws_pricing_mcp" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kagent"
  service_account = "aws-pricing"
  role_arn        = aws_iam_role.aws_pricing_mcp.arn
}

###############################################################################
# aws-eks MCP server (platform/mcp/aws-eks/) — READ-ONLY.
#
# Action list is upstream's own documented "Read-Only Operations Policy"
# (awslabs/mcp, eks-mcp-server README), copied verbatim rather than guessed.
# Their WRITE policy is effectively `eks:*` plus IAMFullAccess/VPCFullAccess —
# deliberately NOT granted here, matching the server's read-only launch args
# (no --allow-write). The capability is withheld at the IAM layer AND the tool
# layer, not just the prompt.
#
# Note: `aws-documentation` gets NO role at all — it needs no AWS identity.
###############################################################################

data "aws_iam_policy_document" "aws_eks_mcp" {
  statement {
    sid    = "EksReadOnly"
    effect = "Allow"
    actions = [
      "eks:DescribeCluster",
      "eks:DescribeInsight",
      "eks:ListInsights",
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeRouteTables",
      "cloudformation:DescribeStacks",
      "cloudwatch:GetMetricData",
      "logs:StartQuery",
      "logs:GetQueryResults",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "eks-mcpserver:QueryKnowledgeBase",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "aws_eks_mcp" {
  name   = "${local.cluster_name}-mcp-aws-eks"
  policy = data.aws_iam_policy_document.aws_eks_mcp.json
}

resource "aws_iam_role" "aws_eks_mcp" {
  name               = "${local.cluster_name}-mcp-aws-eks"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "aws_eks_mcp" {
  role       = aws_iam_role.aws_eks_mcp.name
  policy_arn = aws_iam_policy.aws_eks_mcp.arn
}

resource "aws_eks_pod_identity_association" "aws_eks_mcp" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kagent"
  service_account = "aws-eks"
  role_arn        = aws_iam_role.aws_eks_mcp.arn
}
