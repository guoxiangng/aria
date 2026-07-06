output "repository_urls" {
  description = "ECR repository URLs, keyed by repo name."
  value       = { for k, v in aws_ecr_repository.byo_agents : k => v.repository_url }
}
