terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "aria"
      ManagedBy = "terraform"
      Layer     = "persistent" # NOT destroyed with the cluster — see README.md
    }
  }
}
