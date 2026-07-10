output "state_bucket" {
  description = "S3 bucket for Terraform remote state — put this in infra/02-eks/backend.hcl."
  value       = aws_s3_bucket.tfstate.id
}

output "github_actions_role_arn" {
  description = "Role ARN for GitHub Actions to assume via OIDC (set as a repo variable/secret)."
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_eval_role_arn" {
  description = "Write-scoped role ARN for the eval CI workflow (ECR push + EKS Job apply)."
  value       = aws_iam_role.github_actions_eval.arn
}
