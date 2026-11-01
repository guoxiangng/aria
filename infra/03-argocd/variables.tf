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

# The Azure / Langfuse key variables moved to infra/04-persistent with the secrets they seed
# (2026-11-01). This layer no longer needs any secret input.
