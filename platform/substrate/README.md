# Agent Substrate on ARIA (EKS)

[Agent Substrate](https://github.com/kagent-dev/substrate) is a density/serverless runtime for
kagent agents: instead of one always-on Deployment per agent, agents run as **actors** on a shared
**WorkerPool**, get **snapshotted to object storage when idle**, and **resume on the next call**.

**Verified live on EKS** (`ap-southeast-1`, cluster `aria`, kagent 0.9.10, substrate v0.0.10):
control plane healthy, JWT auth against the EKS OIDC issuer, gVisor actor runtime running on
stock t3.large nodes.

## Deploy model — fully ArgoCD-managed (per ARIA's layering law)

Everything Kubernetes is in the platform layer, deployed by ArgoCD. Terraform is AWS-only.
Nothing here is installed by hand. Four ArgoCD Applications (`gitops/apps/`):

| App | Wave | What |
|-----|------|------|
| `substrate-crds` | 0 | `ate.dev` CRDs (upstream OCI chart, unmodified) |
| `substrate-config` | 0 | ESO `ExternalSecret`s → the 4 cert Secrets ate-api needs |
| `substrate` | 1 | Control + data plane (the vendored chart + `values.yaml`) |
| kagent (`platform/kagent/values.yaml`) | 1 | `controller.substrate` enablement + `kagent-default` WorkerPool |
| `substrate-probe` (`agents/`) | 5 | the probe SandboxAgent (actor) |

### The `lookup` problem, solved in-layer (not by bailing to manual helm)

The upstream chart self-bootstraps its JWT server cert + session-signing keys with Helm
`genCA`/`genSignedCert` + **`lookup`** (reuse-on-upgrade). `lookup` returns empty under ArgoCD's
`helm template` rendering, so ArgoCD would **regenerate the certs on every sync**. Rather than
leave the platform layer, ARIA solves it there:

- `values.yaml` sets `auth.jwt.bootstrap.enabled: false` — the chart stops generating (and stops
  calling `lookup`).
- The four objects it would have made are provided via **ESO from Secrets Manager**: `ateapi-tls`,
  `ateapi-ca`, `session-id-jwt-pool`, `session-id-ca-pool` (`manifests/`). Material is generated
  declaratively by `infra/03-argocd/substrate-certs.tf` (Terraform `tls` provider → Secrets
  Manager) — the same TF→SM→ESO pattern as the kagent secrets. Deterministic, rotatable, no
  churn. The CA bundle (public) is delivered as a Secret too, so the two consumers that mount it
  are patched from ConfigMap→Secret (see `vendor/PATCH.md`).

## Vendored + patched chart (`vendor/`)

`vendor/substrate/` is upstream **v0.0.10** with two small patches (full diff + upstream-sync in
`vendor/PATCH.md`):
1. **valkey parameterized** — upstream hardcodes a 6-node Redis Cluster in its init job; the patch
   drives it from `valkey.replicas`, so ARIA runs 3 masters / 0 replicas to fit the 2× t3.large
   lab (binding constraint is VPC-CNI pod-slots, 35/node — not CPU).
2. **CA bundle mount ConfigMap→Secret** — so the ESO-provided CA works (see above).
`substrate-crds` is used unmodified straight from OCI.

## The `values.yaml` overlay — what ARIA changes vs upstream

- `auth.jwt.issuer` → the **EKS OIDC issuer** (upstream defaults to the stock kind issuer). The
  one EKS-specific knob; with it, JWT mode "just works" — no GKE-only PodCertificate feature-gates
  (that was a v0.0.6-era concern; v0.0.10 documents EKS in the values).
- `auth.jwt.bootstrap.enabled: false` → certs via ESO (see above).
- `valkey.replicas: 3` + `valkey.clusterReplicas: 0` → minimum viable Redis Cluster (no HA).
- `rustfs.enabled: true` → keep the bundled in-cluster S3-compatible snapshot store (bucket
  `ate-snapshots`); **no external AWS S3 bucket or IAM needed** for the spike.

## Fresh-cluster bring-up

`terraform apply` in `infra/03-argocd` (generates certs + seeds Secrets Manager) → ArgoCD syncs
the apps above in wave order → ESO materializes the Secrets → the chart comes up. No manual step.

Verify: `kubectl -n ate-system get pods` (all Running/Completed); valkey healthy
(`kubectl -n ate-system exec valkey-cluster-0 -- valkey-cli cluster info` → `cluster_state:ok`,
`cluster_size:3`); ate-api serving (`kubectl -n ate-system logs deploy/ate-api-server-deployment`
shows `Fetched JWK set` from the EKS OIDC issuer).

## EKS gotcha — node security group blocks cross-node privileged ports by default

After the control plane + ESO certs were healthy, the substrate-enabled kagent controller still
couldn't reach `ate-api` — dialing `dns:///api.ate-system.svc:443` timed out. It was **not** the
mesh and **not** the certs (both directly ruled out: same result meshed and non-meshed, same
result from a plain non-meshed pod in `ate-system` itself). Root cause: the
`terraform-aws-modules/eks` module's node security group **only opens ephemeral ports
(1025-65535) between nodes** by default — any pod serving a privileged port like 443 is
unreachable from a pod on a *different* node until you add a rule for it. `ate-api` was ARIA's
first workload to serve on such a port cross-node, so nothing had exposed this before.

Fixed with one additive rule in `infra/02-eks/main.tf`
(`node_security_group_additional_rules.ingress_self_443`, self-referencing tcp/443 ingress on
the node SG) — confirmed live: cross-node TCP to ate-api:443 failed before, succeeded after,
no other change. AWS-layer, so it's in Terraform per `docs/deploy-layers.md`.

## Identity-model note (tension with ARIA's SPIFFE/Istio plane)

Substrate actors are **not their own Pods** — many actors share a small set of WorkerPool pods,
isolated by **gVisor** (network policy externalized to `agentgateway`), not by per-Pod
ServiceAccount / NetworkPolicy. This differs from the rest of ARIA, where the Pod is the unit of
identity (kagent's per-agent SA; the Istio-ambient SPIFFE plane). A SandboxAgent actor has no
`spec.serviceAccountName` of its own. Reconciling per-agent identity (SA today, SPIFFE later) with
the actor model is an open design question — see `docs/spec-agent-substrate-integration.md` §5.5
and the identity-layer article outline.
