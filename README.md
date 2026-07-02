# ARIA — Agentic Runtime for Infrastructure Automation

Governed InfraOps **agent platform** on kagent — SREs operate the cluster through scoped, audited,
approval-gated natural-language agents, and every agent is deployed through a reusable template that bakes
in RBAC, observability, guardrails, and evaluation.

> Substrate: **Amazon EKS** (managed node groups) in **ap-southeast-1**, **Bedrock** (Claude) as the model.
> Design notes live in `docs/`.

---

## Repo layout

```
aria/
├── BOOTSTRAP.md            # the 0→1 runbook (start here)
├── infra/                  # Terraform (AWS) — NUMBERED = apply order
│   ├── 00-prereqs/         # local tooling install (terraform / aws / kubectl)
│   ├── 01-bootstrap/       # remote state (S3, S3-native lock) + GitHub OIDC role
│   ├── 02-eks/             # EKS + node group + Bedrock/EBS IAM (into existing VPC)
│   └── 03-argocd/          # ArgoCD + repo cred + kagent ns/secret + app-of-apps
├── charts/                 # reusable Helm charts (namespace-bootstrap; agent-template later)
├── gitops/                 # ArgoCD app-of-apps (root-app + apps/) — synced from git
├── envs/                   # per-env values (dev.yaml)
├── platform/               # kagent values + Bedrock ModelConfigs; observability, policies (later)
├── agents/                 # the catalog — one folder per agent (later)
├── eval/                   # shared eval framework (runner, gates)
├── docs/                   # design notes
└── .github/workflows/      # CI
```

## Apply order (from zero)

```bash
# 1. Bootstrap — creates the state bucket + GitHub OIDC role (local state)
cd infra/01-bootstrap
terraform init
terraform apply            # note the output: state_bucket

# 2. Point the EKS layer at the new backend, then stand up the cluster
cd ../02-eks
# put state_bucket into backend.hcl (gitignored), then:
terraform init -backend-config=backend.hcl
terraform apply

# 3. Wire kubectl
aws eks update-kubeconfig --name aria --region ap-southeast-1
kubectl get nodes
```

## Prerequisites
- Terraform >= 1.10, AWS CLI v2, `kubectl`, `helm`
- AWS credentials with rights to create VPC/EKS/IAM/S3 (a `default` profile)
- Bedrock model access enabled in ap-southeast-1 (Claude Sonnet/Haiku) — one-time, in the Bedrock console
- (for CI) a GitHub repo; the bootstrap creates the OIDC role Actions assumes

## Cost note
EKS control plane ~$0.10/hr (~$73/mo) + nodes (2× t3.large **spot**). `terraform destroy` the `eks/` layer
when idle to stop node + control-plane charges; the bootstrap layer (S3) costs ~nothing.
