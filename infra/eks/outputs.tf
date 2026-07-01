output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "update_kubeconfig_command" {
  description = "Run this to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "bedrock_role_arn" {
  description = "IAM role agent pods assume for Bedrock (via Pod Identity)."
  value       = aws_iam_role.bedrock.arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
