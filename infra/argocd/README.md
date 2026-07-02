# infra/argocd

Codifies the GitOps control plane. After this layer applies, **ArgoCD owns everything else from git** —
no more `kubectl`/`helm` by hand.

## What it creates
- **ArgoCD** via the upstream `argo-cd` Helm chart (not vendored; version pinned in `argocd_chart_version`)
- The **app-of-apps** root Application (ridden in as a chart `extraObject`) → ArgoCD then syncs `gitops/`
- **Repo credential** secret so ArgoCD can pull the private repo
- **kagent namespace + Azure OpenAI secret** (platform-core; carries a secret, so Terraform-owned).
  Tenant/agent namespaces are pure CaC via ArgoCD + `charts/namespace-bootstrap`.

## Use
```bash
terraform init -backend-config=backend.hcl
terraform apply    # reads terraform.tfvars (gitignored): repo_pat + azure_openai_api_key
```
Then ArgoCD reconciles: `namespace-bootstrap` (wave -1) → `kagent-crds` (0) → `kagent` (1) → `models` (2).

## Notes / verify
- `azure_openai_api_key` + `repo_pat` come from **gitignored `terraform.tfvars`** (or `TF_VAR_*` env) — never git.
  Later: move to ESO + AWS Secrets Manager (the AIDA pattern) so even this layer holds no secret material.
- **Reconcile the earlier manual ArgoCD** (installed via kubectl during bring-up): so Terraform owns it, run
  `kubectl delete namespace argocd` once, then `terraform apply`. On a fresh cluster this layer just works.
- Verify `argocd_chart_version` against https://github.com/argoproj/argo-helm before apply.
- helm provider pinned to v2.x (v3 changed the provider block syntax).
