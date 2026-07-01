variable "region" {
  description = "AWS region for the state bucket and OIDC role."
  type        = string
  default     = "ap-southeast-1"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform remote state. Change the suffix to make it unique."
  type        = string
  default     = "aria-tfstate"
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the CI role, in 'owner/name' form. Set this before relying on CI."
  type        = string
  default     = "OWNER/aria"
}
