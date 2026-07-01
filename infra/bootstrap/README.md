# infra/bootstrap

Creates the prerequisites the rest of the stack needs, using **local state** (this layer is what
*creates* the remote backend, so it can't use it).

Provisions:
- **S3 bucket** for Terraform remote state (versioned, AES256, public access blocked).
  State **locking is S3-native** (`use_lockfile` in the eks backend) — no DynamoDB.
- **GitHub OIDC provider + IAM role** so GitHub Actions can assume AWS access with no long-lived keys
  (starts as `ReadOnlyAccess` — tighten/extend deliberately later)

## Use

```bash
# terraform.tfvars (gitignored) holds state_bucket_name + region — edit if needed.
terraform init
terraform apply
terraform output   # state_bucket is already prefilled in ../eks/backend.hcl
```

> The S3 bucket name must be globally unique — the default is suffixed with your account id.
> Run this layer rarely; its local `terraform.tfstate` stays here (gitignored).
