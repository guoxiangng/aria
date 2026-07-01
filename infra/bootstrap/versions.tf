terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Bootstrap uses LOCAL state by design — it is what *creates* the remote backend.
  # After apply, the state file lives here in infra/bootstrap/. Commit nothing sensitive.
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "aria"
      ManagedBy = "terraform"
      Layer     = "bootstrap"
    }
  }
}
