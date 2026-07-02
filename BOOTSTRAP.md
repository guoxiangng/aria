# ARIA — 0 → 1 Bootstrap (fully codified)

From nothing (just an AWS account) to a running GitOps-managed agent platform. **No manual `kubectl`/`helm`** —
two `terraform apply`s, then ArgoCD reconciles everything from git.

```
terraform apply infra/bootstrap   ─┐  S3 state bucket + GitHub OIDC role
terraform apply infra/eks          │  VPC(existing) + EKS + nodes + addons + Bedrock IAM
terraform apply infra/argocd       │  ArgoCD + repo cred + kagent ns/secret + app-of-apps
        │                          ┘
        ▼  ArgoCD then syncs gitops/ by sync-wave:
   wave -1  namespace-bootstrap   (charts/namespace-bootstrap + envs/dev.yaml)   → agent namespaces
   wave  0  kagent-crds           (upstream OCI chart)
   wave  1  kagent                (upstream OCI chart + platform/kagent/values.yaml)
   wave  2  models                (Bedrock ModelConfig CRs)
   wave  5  agents                (later — our InfraOps agents)
```

## Prerequisites (once)
- Terraform ≥ 1.10, AWS CLI v2, `kubectl` (only to *observe*; not to deploy)
- Bedrock model access enabled in ap-southeast-1 (Sonnet 4.6, Haiku 4.5)
- A GitHub **PAT** (repo read) for ArgoCD to pull this private repo
- Azure OpenAI API key (from the LADP `.env`)

## Steps
```bash
# 1. state backend
cd infra/bootstrap && terraform init && terraform apply

# 2. cluster (into existing gx-network VPC)
cd ../eks && terraform init -backend-config=backend.hcl && terraform apply

# 3. GitOps control plane  (terraform.tfvars holds repo_pat + azure_openai_api_key — gitignored)
cd ../argocd && terraform init -backend-config=backend.hcl && terraform apply
```
That's it. Watch ArgoCD converge:
```bash
kubectl -n argocd get applications        # observe only
kubectl -n kagent get pods
```

## What lives where (CaC map)
| Layer | Owns | Mechanism |
|-------|------|-----------|
| `infra/bootstrap` | state bucket, GitHub OIDC | Terraform |
| `infra/eks` | VPC use, EKS, nodes, addons, Bedrock/EBS IAM | Terraform |
| `infra/argocd` | ArgoCD, repo cred, kagent ns + Azure secret, app-of-apps | Terraform |
| `charts/namespace-bootstrap` | agent namespaces (quota/limitrange/SA/RBAC) | Helm, via ArgoCD |
| `platform/kagent` | kagent values + Bedrock ModelConfigs | ArgoCD (upstream OCI chart + our values) |
| `agents/` | agent CRs | ArgoCD (later) |

## Secrets (never in git)
- `repo_pat`, `azure_openai_api_key` → gitignored `infra/argocd/terraform.tfvars` (or `TF_VAR_*`).
- Next hardening: move both to **ESO + AWS Secrets Manager** (the AIDA pattern) so no secret sits in tfvars.

## Reconcile note
ArgoCD was hand-installed during bring-up. To hand ownership to Terraform: `kubectl delete namespace argocd`
once, then `terraform apply infra/argocd`. On a fresh cluster, step 3 just works.
