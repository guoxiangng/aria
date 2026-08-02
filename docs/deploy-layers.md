# ARIA — Deploy Layers (the layering law)

> The one rule that decides *where any piece of the system is defined and how it gets deployed*.
> If you're adding anything to ARIA, read this first. See `repo-structure.md` for the folder map.

## The law

ARIA has exactly **two deploy layers**, and every artifact belongs to one:

| Layer | Owns | Tooling | Folder(s) |
|-------|------|---------|-----------|
| **1 — Infra / AWS** | AWS resources only | **Terraform** | `infra/` |
| **2 — Platform / Kubernetes** | *everything* that runs on the cluster | **ArgoCD** (GitOps) | `gitops/`, `platform/`, `charts/`, `agents/`, `envs/` |

Two sentences decide everything:

1. **Is it an AWS resource?** → Terraform (`infra/`). VPC, EKS, IAM, Pod Identity, Secrets
   Manager, ECR, StorageClass backing, ArgoCD's own install.
2. **Does it run on the cluster (a Kubernetes object)?** → the platform layer, deployed by
   **ArgoCD**. Operators, CRs, Deployments, Secrets, ConfigMaps, policies, agents — **all of it**.

There is **no third layer.** "Install it by hand with `helm`/`kubectl` just this once" is not a
category. If a Kubernetes thing is hard to put under ArgoCD, that is a **problem to solve inside
the platform layer**, not a licence to leave it.

## Why so strict

The whole point of ARIA is *reproducible-from-code in a fresh cluster*. A manual `helm install`
or an out-of-band `kubectl apply` is invisible to that promise: it works on the cluster that
happens to have had the command run, and silently doesn't exist anywhere else. One exception and
the guarantee is gone. So the bar to deviate is not "it's annoying" — it's the two questions above.

## The two *principled* narrowings (not exceptions to the law — consequences of it)

These live in Terraform because they are genuinely **AWS-layer**, not because we're dodging ArgoCD:

- **The irreducible bootstrap kernel** — ArgoCD itself, the cluster, IAM/Pod-Identity roles,
  StorageClass. ArgoCD can't deploy ArgoCD; something has to create the cluster ArgoCD runs on.
  This is the smallest possible seed and nothing else hides in it.
- **Secret / cert *material* generation + storage** — a public git repo cannot hold secret values,
  so the material must originate somewhere AWS-backed. Terraform generates it (e.g. the `tls`
  provider for certs) and seeds **AWS Secrets Manager**; that's an AWS-layer action. The resulting
  **Kubernetes Secret is still platform-layer** — created by ESO from Secrets Manager, pointed at
  by a git-committed `ExternalSecret` (no material in git). Material in TF/AWS; the K8s object in
  ArgoCD.

## Worked example — Agent Substrate (how a hard case is solved *in-layer*)

Substrate's Helm chart fought GitOps two ways. Neither was allowed to break the law:

1. **Hardcoded 6-node valkey** (no value overrides it) → **vendor + patch** the chart
   (`platform/substrate/vendor/`, one parameterizing diff), still deployed by ArgoCD. Not a manual
   install — a fixed chart, in the platform layer. See `vendor/PATCH.md`.
2. **JWT cert self-bootstrap via Helm `lookup`** → `lookup` returns empty under ArgoCD's
   `helm template`, so certs would regenerate every sync. The *wrong* fix is "install the chart by
   hand so `lookup` works." The **in-layer** fix: disable the chart's bootstrap
   (`auth.jwt.bootstrap.enabled=false`) and provide the four cert objects via **ESO from Secrets
   Manager** — material generated declaratively by `infra/03-argocd/substrate-certs.tf` (TF `tls`
   provider → SM; the AWS-layer narrowing above), K8s Secrets synced by ESO (platform layer).
   Deterministic, no churn, reproducible on a fresh cluster. See `platform/substrate/README.md`.

The lesson: when a chart resists GitOps, the move is **configure it, vendor-and-patch it, or
provide its inputs another declarative way** — never leave the layer.

## Platform-layer conventions

- **Prefer upstream charts + a values overlay.** ArgoCD multi-source: source #1 = this repo as
  `$values`, source #2 = the upstream OCI/HTTP chart, pinned. Our values live in `platform/<x>/`.
  (kagent, istio.) Keep overlays thin.
- **Vendor a chart only when values can't express what's needed** (hardcoded behaviour). Vendored
  charts go in `platform/<x>/vendor/`, carry a `PATCH.md` (upstream version + exact diff), keep the
  diff minimal, mark every edit `ARIA-PATCH`, and stay upstream-syncable. Vendoring is a cost
  (manual re-sync on bumps) — justify it.
- **Secrets never in git.** TF → Secrets Manager → ESO → K8s Secret; git holds only the
  `ExternalSecret` pointer. (kagent secrets, substrate certs.)
- **Sync waves:** 0 = platform/infra-on-cluster (CRDs, mesh, ESO config, operators), 1 = operators
  needing them (kagent, substrate), 5 = agents. Higher waves depend on lower.
- **Reusable charts** (`charts/`) are ARIA's own (namespace-bootstrap, agent-template); env
  differences live in `envs/<env>.yaml` overlays, never forked charts.

## Quick test before you add something

> "If I deleted the cluster and re-ran `terraform apply` + let ArgoCD sync from git, would this
> come back **exactly**, with no manual step?" If no, it's in the wrong place.
