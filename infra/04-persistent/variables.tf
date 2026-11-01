variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "byo_agent_repos" {
  description = "ECR repo names for BYO agent images, one per agent. Add new agents here as they're built."
  type        = list(string)
  default     = ["aria/investigation-loop", "aria/eval-runner", "aria/strands-investigator"]
}

variable "cluster_name" {
  description = "Names the ESO IAM role (<cluster_name>-external-secrets). The cluster itself lives in infra/02-eks."
  type        = string
  default     = "aria"
}

# --- Seed values for three Secrets Manager secrets (secrets.tf). Read only when a secret is first
# created; after that Secrets Manager is the source of truth (ignore_changes), so these can be stale.
# Provide via gitignored terraform.tfvars or TF_VAR_*.

variable "azure_openai_api_key" {
  description = "Azure OpenAI API key -> aria/kagent-azure-openai. Azure was retired 2026-09; kept only so the secret can be re-seeded."
  type        = string
  sensitive   = true
}
# NOTE: there is deliberately NO variable for the Azure EMBEDDING key. That secret's value is written
# directly to Secrets Manager with the CLI (see the comment in secrets.tf), so it never enters tfvars or
# Terraform state.

variable "langfuse_public_key" {
  description = "Langfuse public key (pk-lf-...) for OTel trace export."
  type        = string
  sensitive   = true
}

variable "langfuse_secret_key" {
  description = "Langfuse secret key (sk-lf-...) for OTel trace export."
  type        = string
  sensitive   = true
}
