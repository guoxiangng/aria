###############################################################################
# Bedrock access for the LiteLLM model gateway (platform/litellm/, domain 10)
#
# LiteLLM calls Bedrock for three of the Auto Router's four tiers. It gets credentials the same way
# every other AWS caller here does — EKS Pod Identity, no static keys — by binding its ServiceAccount
# (litellm/litellm, created by platform/litellm/deployment.yaml) to the EXISTING aria-bedrock role in
# main.tf. A role can carry several associations, so this adds one rather than reusing
# aws_eks_pod_identity_association.bedrock, whose namespace/SA come from shared variables other work
# depends on.
#
# Apply on its own:
#   terraform apply -target=aws_eks_pod_identity_association.litellm_bedrock
# A plain `terraform apply` would also apply whatever else is pending in this layer.
###############################################################################

resource "aws_eks_pod_identity_association" "litellm_bedrock" {
  cluster_name    = module.eks.cluster_name
  namespace       = "litellm"
  service_account = "litellm"
  role_arn        = aws_iam_role.bedrock.arn
}
