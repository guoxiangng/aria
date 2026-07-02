# infra/03-argocd

Codifies the GitOps control plane. After this layer applies, **ArgoCD owns everything else from git** —
no more `kubectl`/`helm` by hand.

## What it creates
- **ArgoCD** via the upstream `argo-cd` Helm chart (not vendored; version in `argocd_chart_version`, default 10.1.0)
- The **app-of-apps** root Application (ridden in as a chart `extraObject`) → ArgoCD then syncs `gitops/`
- **kagent namespace + Azure OpenAI secret** (platform-core; carries a secret, so Terraform-owned).
  Tenant/agent namespaces are pure CaC via ArgoCD + `charts/namespace-bootstrap`.

> The repo is **public**, so ArgoCD pulls it anonymously — no repo credential needed.

## Use
```bash
terraform init -backend-config=backend.hcl
terraform apply    # reads terraform.tfvars (gitignored): azure_openai_api_key
```
Then ArgoCD reconciles: `namespace-bootstrap` (wave -1) → `kagent-crds` (0) → `kagent` (1) → `models` (2).

## Notes / verify
- `azure_openai_api_key` comes from **gitignored `terraform.tfvars`** (or `TF_VAR_*` env) — never git.
  Later: move to ESO + AWS Secrets Manager (the AIDA pattern) so this layer holds no secret material.
- Verify `argocd_chart_version` against https://github.com/argoproj/argo-helm before apply.
- helm provider pinned to v2.x (v3 changed the provider block syntax).
