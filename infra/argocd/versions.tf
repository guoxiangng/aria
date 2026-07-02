terraform {
  required_version = ">= 1.10"

  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.70" }
    helm       = { source = "hashicorp/helm", version = "~> 2.16" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.33" }
  }
}

provider "aws" {
  region = var.region
}

# Cluster (created by infra/eks) — used to configure the k8s + helm providers.
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}
data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
