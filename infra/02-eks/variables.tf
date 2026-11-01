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
  default     = "1.36"
}

# --- Existing network (gx-network:Vpc1) — real values in terraform.tfvars (gitignored) ---
variable "vpc_id" {
  description = "Existing VPC to deploy EKS into."
  type        = string
}

variable "private_subnet_ids" {
  description = "Existing private subnet IDs (>=2 AZs) for the EKS control-plane ENIs + nodes."
  type        = list(string)
}

# --- Managed node group sizing (lab defaults: small + spot for cost) ---
variable "node_subnet_ids" {
  description = <<-EOT
    Subnets for the NODES only; empty = the same as private_subnet_ids. The control plane still needs
    >=2 AZs, the nodes don't. Single AZ keeps a small fleet next to its data: EBS volumes are bound to
    one AZ, so with 2 nodes over 3 AZs a database's volume can sit in an AZ with no node — and a spot
    replacement can land in the wrong AZ. Trade-off: no AZ redundancy (fine for a POC).
  EOT
  type        = list(string)
  default     = []
}

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
  default = 1
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
