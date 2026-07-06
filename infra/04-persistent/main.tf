###############################################################################
# ECR repos for BYO agent images. This layer is DURABLE — it must survive
# `terraform destroy` of infra/02-eks, so images aren't lost when the cluster
# is torn down for cost control. See docs/repo-structure.md.
###############################################################################

resource "aws_ecr_repository" "byo_agents" {
  for_each = toset(var.byo_agent_repos)

  name                 = each.value
  image_tag_mutability = "MUTABLE" # lab convenience; consider IMMUTABLE once this matters more
  force_delete         = true      # lab: allow `terraform destroy` even with images present

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "byo_agents" {
  for_each = aws_ecr_repository.byo_agents

  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "expire untagged images after 14 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 14
      }
      action = { type = "expire" }
    }]
  })
}
