# ARIA — Repo Structure & Layering

Single repo, but organized by the same **layers** the AIDA-on-OpenShift setup splits across three repos
(`cak-platform-cac`, `aida-ckn-deploy`, `aida-platform-agent-configs`). We keep their proven abstractions;
we don't need their repo boundaries.

```
aria/
├── infra/                    # Terraform (AWS), numbered = apply order:
│   │                         #   00-prereqs, 01-bootstrap, 02-eks, 03-argocd, 04-persistent (ECR, durable)
│   │                         #   [ARIA-only; AIDA gets clusters from ACM/HCP]
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

## Identity / mesh layer (`platform/istio/`, `platform/external-secrets/`) — LIVE
- **Istio ambient mesh** (`platform/istio/`, `gitops/apps/istio.yaml`) — the `ambient` umbrella chart
  (base + istiod + istio-cni + ztunnel, one release). Every meshed pod gets a per-agent **SPIFFE identity**
  (`spiffe://cluster.local/ns/<ns>/sa/<sa>`) and automatic A2A **mTLS** via the per-node ztunnel — no
  sidecars, no pod restarts. The `kagent` namespace is enrolled via the `istio.io/dataplane-mode=ambient`
  label (set in `envs/dev.yaml`).
- **AuthorizationPolicy allow-lists** (`platform/istio/policies/`, `gitops/apps/istio-policies.yaml`) —
  identity-based access control. First one: `cluster-diagnostics` accepts calls ONLY from the
  incident-commander SPIFFE principal (default-deny for everyone else). Reachability constrained by
  cryptographic identity, not network position.
- **External Secrets Operator** (`platform/external-secrets/`, `gitops/apps/external-secrets*.yaml`) —
  secret material lives in **AWS Secrets Manager** (seeded by `infra/03-argocd/eso.tf`); ESO syncs it into
  k8s Secrets via git-committed `ExternalSecret` pointer CRs, authenticated by **EKS Pod Identity** (no
  static keys). Secrets are OUT of Terraform state entirely.

## The kagent namespace migration (done this iteration)
The `kagent` namespace + its secrets used to be Terraform-owned (`infra/03-argocd`) — the only cluster
constructs outside GitOps, because a public repo can't hold secret values. ESO dissolved that coupling:
secrets moved to Secrets Manager, and the namespace moved to pure CaC (`charts/namespace-bootstrap` via
`envs/dev.yaml`, migrated with `terraform state rm` so the live namespace was never deleted). The chart's
quota/limitrange are now **opt-in per namespace** so the platform namespace runs unconstrained. Terraform
now holds only the irreducible bootstrap kernel (ArgoCD install, StorageClass, IAM/Pod-Identity roles).

## Deferred (not yet, but reserved above)
- ~~`gitops/` (ArgoCD)~~ — done, live since `infra/03-argocd`.
- ~~`infra/persistent/` (ECR for BYO agent images)~~ — done, live as `infra/04-persistent`.
- ~~**Secrets → ESO + AWS Secrets Manager**~~ — DONE (see the identity/mesh section above).
- `platform/operators/` cert-manager — only when we need TLS beyond the EKS-issued cert.
