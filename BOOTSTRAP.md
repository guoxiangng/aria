# ARIA — 0 → 1 Bootstrap (fully codified)

From nothing (just an AWS account) to a running GitOps-managed agent platform. **No manual `kubectl`/`helm`** —
two `terraform apply`s, then ArgoCD reconciles everything from git.

```
terraform apply infra/01-bootstrap   ─┐  S3 state bucket + GitHub OIDC role
terraform apply infra/02-eks          │  VPC(existing) + EKS + nodes + addons + Bedrock IAM
terraform apply infra/03-argocd       │  ArgoCD + repo cred + kagent ns/secret + app-of-apps
        │                          ┘
        ▼  ArgoCD then syncs gitops/ by sync-wave:
   wave -1  namespace-bootstrap   (charts/namespace-bootstrap + envs/dev.yaml)   → agent namespaces
   wave  0  kagent-crds           (upstream OCI chart)
   wave  1  kagent                (upstream OCI chart + platform/kagent/values.yaml)
   wave  2  models                (Bedrock ModelConfig CRs)
   wave  5  agents                (later — our InfraOps agents)
```

## Prerequisites (once)
- **Local tooling** — run `infra/00-prereqs/install-prereqs.ps1` (installs terraform, aws, kubectl).
  helm is NOT required — ArgoCD renders charts server-side.
- Bedrock model access enabled in ap-southeast-1 (Sonnet 4.6, Haiku 4.5)
- A GitHub **PAT** (repo read) for ArgoCD to pull this private repo
- Azure OpenAI API key (from the LADP `.env`)

## Steps
```bash
# 0. tooling (once)
powershell -ExecutionPolicy Bypass -File infra/00-prereqs/install-prereqs.ps1

# 1. state backend
cd infra/01-bootstrap && terraform init && terraform apply

# 2. cluster (into existing gx-network VPC)
cd ../02-eks && terraform init -backend-config=backend.hcl && terraform apply

# 3. GitOps control plane  (terraform.tfvars holds repo_pat + azure_openai_api_key — gitignored)
cd ../03-argocd && terraform init -backend-config=backend.hcl && terraform apply
```
That's it. Watch ArgoCD converge:
```bash
kubectl -n argocd get applications        # observe only
kubectl -n kagent get pods
```

## What lives where (CaC map)
| Layer | Owns | Mechanism |
|-------|------|-----------|
| `infra/01-bootstrap` | state bucket, GitHub OIDC | Terraform |
| `infra/02-eks` | VPC use, EKS, nodes, addons, Bedrock/EBS IAM | Terraform |
| `infra/03-argocd` | ArgoCD, repo cred, kagent ns + Azure secret, app-of-apps | Terraform |
| `charts/namespace-bootstrap` | agent namespaces (quota/limitrange/SA/RBAC) | Helm, via ArgoCD |
| `platform/kagent` | kagent values + Bedrock ModelConfigs | ArgoCD (upstream OCI chart + our values) |
| `agents/` | agent CRs | ArgoCD (later) |

## Secrets (never in git)
- `repo_pat`, `azure_openai_api_key` → gitignored `infra/03-argocd/terraform.tfvars` (or `TF_VAR_*`).
- Next hardening: move both to **ESO + AWS Secrets Manager** (the AIDA pattern) so no secret sits in tfvars.

## Reconcile note
ArgoCD was hand-installed during bring-up. To hand ownership to Terraform: `kubectl delete namespace argocd`
once, then `terraform apply infra/03-argocd`. On a fresh cluster, step 3 just works.
