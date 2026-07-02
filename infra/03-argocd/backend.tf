# Partial S3 backend — same bucket as the other layers, different key. Init with:
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {}
}
