# Remote state backend — PARTIAL config. Account-specific values live in backend.hcl (gitignored).
# Initialize with:  terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {}
}
