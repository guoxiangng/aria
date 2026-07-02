variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "cluster_name" {
  type    = string
  default = "aria"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version (argoproj/argo-helm). VERIFY latest before apply."
  type        = string
  default     = "7.8.2"
}

variable "repo_url" {
  description = "Git repo ArgoCD syncs from."
  type        = string
  default     = "https://github.com/guoxiangng/aria.git"
}

variable "repo_username" {
  description = "GitHub username for the repo credential."
  type        = string
  default     = "guoxiangng"
}

variable "repo_pat" {
  description = "GitHub PAT (repo read scope) for ArgoCD to pull the private repo."
  type        = string
  sensitive   = true
}

variable "azure_openai_api_key" {
  description = "Azure OpenAI API key -> kagent-azure-openai secret. Provide via gitignored terraform.tfvars or TF_VAR_azure_openai_api_key."
  type        = string
  sensitive   = true
}
