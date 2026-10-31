terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.x here, unlike the other layers' ~> 5.70: the fck-nat module needs >= 6.0 (resource-level
      # `region`). Safe in isolation — each layer has its own state and lock file.
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "aria"
      ManagedBy = "terraform"
      Layer     = "nat" # NOT destroyed with the cluster — see README.md
    }
  }
}
