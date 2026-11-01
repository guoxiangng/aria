# infra/04-persistent

**Durable** layer — resources here must survive `terraform destroy` of `infra/02-eks` and
`infra/03-argocd` (the cluster teardown). Nothing here needs the cluster to exist.

## What it creates
- One ECR repo per entry in `byo_agent_repos` (default: `aria/investigation-loop`)
- A lifecycle policy expiring untagged images after 14 days (keeps storage cost near zero for a lab)
- **All `aria/*` Secrets Manager secrets + the ESO IAM role that reads them** (`secrets.tf`,
  `substrate-certs.tf`). Moved here from `03-argocd` on 2026-11-01 with `terraform state mv` (no AWS
  change). Why: five values were set by hand with the CLI and would be lost on destroy, and Secrets
  Manager reserves a deleted name for 7–30 days, so a rebuild couldn't recreate them. ESO's Pod Identity
  binding stays in `03-argocd/eso.tf` because it's tied to the cluster.
- Seed values for three of the secrets come from gitignored `terraform.tfvars` (see the `.example`);
  they're only read when a secret is first created.

## Use
```bash
terraform init -backend-config=backend.hcl
terraform apply
terraform output repository_urls
```

## Adding a new BYO agent's image repo later
Add its name to `byo_agent_repos` in `terraform.tfvars`, `terraform apply`. Existing repos are untouched
(uses `for_each`, not a list index).

## Building and pushing an image (manual for now — no CI yet)
```bash
REGION=ap-southeast-1
ACCOUNT_ID=622629043701
REPO=aria/investigation-loop

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

cd agents/investigation-loop
docker build -t $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:latest .
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:latest
```

## Node → ECR pull permission
EKS managed node groups (via the `terraform-aws-modules/eks/aws` module) attach
`AmazonEC2ContainerRegistryReadOnly` to the node role by default, so nodes can pull from ECR with no
extra IAM. If a BYO agent pod shows `ImagePullBackOff`, check this first — it would be the first thing
to verify, not assume.
