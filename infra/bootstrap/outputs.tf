output "state_bucket" {
  description = "S3 bucket for Terraform remote state — put this in infra/eks/backend.hcl."
  value       = aws_s3_bucket.tfstate.id
}

output "github_actions_role_arn" {
  description = "Role ARN for GitHub Actions to assume via OIDC (set as a repo variable/secret)."
  value       = aws_iam_role.github_actions.arn
}
