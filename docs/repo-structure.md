# ARIA — Repo Structure & Layering

Single repo, but organized by the same **layers** the AIDA-on-OpenShift setup splits across three repos
(`cak-platform-cac`, `aida-ckn-deploy`, `aida-platform-agent-configs`). We keep their proven abstractions;
we don't need their repo boundaries.

```
aria/
├── infra/                    # Terraform (AWS): bootstrap + eks   [ARIA-only; AIDA gets clusters from ACM/HCP]
├── charts/                   # reusable Helm charts
│   ├── namespace-bootstrap/  #   D1: Namespace + ResourceQuota + LimitRange + SA + RBAC + NetworkPolicy
│   └── agent-template/       #   the chart every agent renders through (bakes D1–D4) — ARIA's key abstraction
├── platform/                 # platform instantiation (install + configure)
│   ├── operators/            #   install kagent, kyverno (+ cert-manager/ESO later) via Helm releases
│   ├── kagent/               #   kagent install values + default ModelConfig (→ Bedrock via Pod Identity)
│   ├── observability/        #   Langfuse + OTel
│   └── policies/             #   Kyverno ClusterPolicies (D2/D4 enforcement)
├── agents/                   # kagent Agent instances — one folder per agent (values + content-pack/)
├── eval/                     # shared eval framework (runner, gates)
├── envs/                     # per-env value overlays (dev.yaml, …)
├── gitops/                   # ArgoCD Applications + app-of-apps + sync-waves (when ArgoCD lands)
└── .github/workflows/        # CI: lint → policy → eval → guardrail
```

## Layer mapping to AIDA (what we reuse)

| ARIA folder | AIDA source | Pattern reused |
|---|---|---|
| `charts/namespace-bootstrap/` | `cak-platform-cac/charts/namespace-bootstrap/` | ns+quota+limitrange+SA+RBAC Helm chart (D1) |
| `platform/operators/` | `cak-platform-cac/operators/` + `operator-configs/` | install-vs-configure split |
| `platform/kagent/` | `cak-platform-cac/operator-configs/kagent/` + `aida-platform-agent-configs/.../model-config.yaml` | kagent install + ModelConfig |
| `agents/<agent>/` | `aida-platform-agent-configs/<group>/` | kagent Agent CRs, per-agent folder |
| `envs/` | `cak-platform-cac/envs/dev.yaml` | env value overlays |
| `gitops/` | `*/argocd-apps/` | ArgoCD Application per unit, sync-waves (0=platform, 5=agents) |

## Where ARIA improves on the AIDA pattern

1. **`charts/agent-template/`** — AIDA hand-authors each `Agent` CR (~150 lines). ARIA renders agents from a
   single templated chart + per-agent values + content-pack, baking D1–D4 (scoped SA, `requireApproval`,
   OTel, labels). Adding an agent = a `values.yaml` + a content-pack, not a bespoke CR.
2. **Bedrock via EKS Pod Identity (no API key).** AIDA routes via Portkey + an `apiKeySecret`. ARIA binds the
   agent SA to the `aria-bedrock` IAM role (Pod Identity); the AWS credential chain supplies Bedrock access —
   no static key, no gateway. (Portkey can be re-added later if we want central cost/routing across providers.)

## Deferred (not yet, but reserved above)
- ~~`gitops/` (ArgoCD)~~ — done, live since `infra/03-argocd`.
- **Secrets → ESO + AWS Secrets Manager** (the AIDA pattern). Currently `infra/03-argocd/terraform.tfvars`
  holds `azure_openai_api_key` / `langfuse_public_key` / `langfuse_secret_key` in plaintext (gitignored, but
  still local plaintext + raw Terraform state). Target:
  - Terraform creates the values in **AWS Secrets Manager** instead of a `kubernetes_secret` directly.
  - **ESO** installed in `platform/operators/` (Helm, like kagent), authenticated via **Pod Identity**
    (same no-static-key pattern as Bedrock/EBS-CSI — a dedicated IAM role, no keys).
  - An `ExternalSecret` CR (git-committed, no secret material) per secret tells ESO which Secrets Manager
    path to sync into which K8s Secret name.
  - **No change needed in `platform/kagent/values.yaml`** — it already references secrets by name
    (`kagent-azure-openai`, `kagent-langfuse-otel`); ESO just becomes what populates them.
  - Payoff: rotation happens in AWS, ESO auto-syncs, no `terraform apply` / redeploy needed.
- `platform/operators/` cert-manager — only when we need TLS beyond the EKS-issued cert.
