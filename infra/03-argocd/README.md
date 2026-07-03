# infra/03-argocd

Codifies the GitOps control plane. After this layer applies, **ArgoCD owns everything else from git** —
no more `kubectl`/`helm` by hand.

## What it creates
- **ArgoCD** via the upstream `argo-cd` Helm chart (not vendored; version in `argocd_chart_version`, default 10.1.0)
- The **app-of-apps** root Application (ridden in as a chart `extraObject`) → ArgoCD then syncs `gitops/`
- **kagent namespace + Azure OpenAI secret** (platform-core; carries a secret, so Terraform-owned).
  Tenant/agent namespaces are pure CaC via ArgoCD + `charts/namespace-bootstrap`.
- **`kagent-langfuse-otel` secret** — precomputed `OTEL_EXPORTER_OTLP_HEADERS` (Basic-Auth for Langfuse's
  OTLP endpoint). Referenced via `controller.env` in `platform/kagent/values.yaml`, but kagent's chart
  propagates the platform-level `otel:` config (endpoint/protocol/headers) into **every Declarative/built-in
  agent pod's env** too (confirmed: `OTEL_EXPORTER_OTLP_TRACES_*` + the header all appear on agent pods,
  not just the controller) — that's what actually emits GenAI traces, since LLM calls happen in the agent
  pod's ADK runtime, not the controller.

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

## Langfuse tracing — VERIFIED working (env-var header fallback confirmed)
Checked directly on an agent pod (`k8s-agent`): `OTEL_EXPORTER_OTLP_HEADERS` (Basic-Auth, from the
`kagent-langfuse-otel` secret), `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`, `_PROTOCOL`, `_INSECURE` all land
correctly, and the pod's own logs show `Created new TracerProvider` with the right endpoint/protocol. No
collector-relay needed.

One correction applied: kagent injects the endpoint as the **signal-specific** env var
(`OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`), which per the OTel spec is used **as-is, no `/v1/traces`
auto-append** (that only happens for the general `OTEL_EXPORTER_OTLP_ENDPOINT`). Langfuse's own docs
confirm this — the signal-specific endpoint must include `/v1/traces` explicitly. Fixed in
`platform/kagent/values.yaml` (`endpoint: ".../api/public/otel/v1/traces"`).

To re-verify after any endpoint change: check an agent pod's logs for `TracerProvider`/export lines
(`kubectl -n kagent logs <agent-pod>`), and check the Langfuse UI (Tracing tab) after invoking that agent.
