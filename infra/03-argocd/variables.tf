variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "cluster_name" {
  type    = string
  default = "aria"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version (argoproj/argo-helm). Verified: 10.1.0 = Argo CD v3.0.0 (Jul 2026)."
  type        = string
  default     = "10.1.0"
}

variable "azure_openai_api_key" {
  description = "Azure OpenAI API key -> kagent-azure-openai secret. Provide via gitignored terraform.tfvars or TF_VAR_azure_openai_api_key."
  type        = string
  sensitive   = true
}
