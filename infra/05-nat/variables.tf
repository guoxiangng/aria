variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "vpc_id" {
  description = "The existing VPC ARIA runs in (gx-network:Vpc1). Same value as infra/02-eks."
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet the NAT instance lives in (gx-network:Vpc1:PublicSubnet1)."
  type        = string
}

variable "private_route_table_id" {
  description = "Route table of the private subnets the EKS nodes use — its 0.0.0.0/0 route is pointed at the NAT instance."
  type        = string
}

variable "instance_type" {
  description = "Graviton is what fck-nat's AMI is built for. A nano is ample for a POC's egress."
  type        = string
  default     = "t4g.nano"
}
