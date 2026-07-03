# infra/03-argocd

Codifies the GitOps control plane. After this layer applies, **ArgoCD owns everything else from git** —
no more `kubectl`/`helm` by hand.

## What it creates
- **ArgoCD** via the upstream `argo-cd` Helm chart (not vendored; version in `argocd_chart_version`, default 10.1.0)
- The **app-of-apps** root Application (ridden in as a chart `extraObject`) → ArgoCD then syncs `gitops/`
- **kagent namespace + Azure OpenAI secret** (platform-core; carries a secret, so Terraform-owned).
  Tenant/agent namespaces are pure CaC via ArgoCD + `charts/namespace-bootstrap`.
- **`kagent-langfuse-otel` secret** — precomputed `OTEL_EXPORTER_OTLP_HEADERS` (Basic-Auth for Langfuse's
  OTLP endpoint), injected into the controller via `platform/kagent/values.yaml` (`controller.env`).

> The repo is **public**, so ArgoCD pulls it anonymously — no repo credential needed.

## Use
```bash
terraform init -backend-config=backend.hcl
terraform apply    # reads terraform.tfvars (gitignored): azure_openai_api_key, langfuse_{public,secret}_key
```
Then ArgoCD reconciles: `namespace-bootstrap` (wave -1) → `kagent-crds` (0) → `kagent` (1) → `models` (2).

## Notes / verify
- Secrets come from **gitignored `terraform.tfvars`** (or `TF_VAR_*` env) — never git.
  Later: move to ESO + AWS Secrets Manager (the AIDA pattern) so this layer holds no secret material.
- Verify `argocd_chart_version` against https://github.com/argoproj/argo-helm before apply.
- helm provider pinned to v2.x (v3 changed the provider block syntax).

## Langfuse tracing — UNVERIFIED, check after deploy
kagent's Helm chart has no `headers` field for the OTLP exporter, and Langfuse's OTLP endpoint requires a
Basic-Auth header. We inject it via the standard `OTEL_EXPORTER_OTLP_HEADERS` env var, which the underlying
Go OTel SDK reads as a fallback — **but this isn't confirmed against kagent's actual source**. After apply:
1. `kubectl -n kagent logs -l app.kubernetes.io/component=controller | grep -i otel` — look for export
   errors (401 = header not picked up; connection refused = endpoint/protocol wrong).
2. Check the Langfuse UI (Tracing tab) for new traces after invoking any agent.
3. If nothing lands: the fallback is an in-cluster **OTel Collector relay** (kagent → no-auth OTLP → Collector
   adds the header via its own exporter config → Langfuse) — more reliable, more moving parts.
