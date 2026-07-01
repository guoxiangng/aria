variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "cluster_name" {
  type    = string
  default = "aria"
}

variable "cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.32"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

# --- Managed node group sizing (lab defaults: small + spot for cost) ---
variable "node_instance_types" {
  type    = list(string)
  default = ["t3.large"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
  default     = "SPOT"
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_desired_size" {
  type    = number
  default = 2
}

# --- Bedrock access for agent pods (EKS Pod Identity) ---
variable "enable_bedrock_pod_identity" {
  description = "Create the Pod Identity association now. Leave false until the kagent namespace/SA exists, then flip to true."
  type        = bool
  default     = false
}

variable "agent_namespace" {
  description = "Namespace whose ServiceAccount gets Bedrock access via Pod Identity."
  type        = string
  default     = "kagent"
}

variable "agent_service_account" {
  description = "ServiceAccount name granted Bedrock access."
  type        = string
  default     = "kagent"
}
