variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "byo_agent_repos" {
  description = "ECR repo names for BYO agent images, one per agent. Add new agents here as they're built."
  type        = list(string)
  default     = ["aria/investigation-loop"]
}
