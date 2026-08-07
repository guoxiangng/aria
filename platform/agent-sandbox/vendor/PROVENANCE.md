# Vendored: Agent Sandbox v0.5.4 (upstream manifest, UNMODIFIED)

`sandbox-with-extensions.yaml` is the upstream release manifest, byte-for-byte unmodified.

| | |
|---|---|
| Project | [kubernetes-sigs/agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox) (Kubernetes SIG Apps subproject) |
| Version | **v0.5.4** (released 2026-07-30) |
| Source | `https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v0.5.4/sandbox-with-extensions.yaml` |
| sha256 | `7ada631db5d5a2cc043f48ca05cec94db54bc0afa4756b3b610c920b188fe2c4` |
| Contents | 15 resources: 4 CRDs, 1 controller Deployment, Namespace, SA, 2 ClusterRole(+Binding), Role(+Binding), 2 Services |
| Controller image | `registry.k8s.io/agent-sandbox/agent-sandbox-controller:v0.5.4` |

## Why vendored (not referenced upstream)

Upstream ships a plain `kubectl apply -f <github-release-URL>` manifest — **no Helm chart** (verified
at v0.5.4). ArgoCD cannot sync a remote GitHub-release URL as a source (it needs git/Helm/OCI), and
ARIA's layering law (`docs/deploy-layers.md`) says all Kubernetes objects deploy via ArgoCD — no
manual `kubectl apply` tier. So the manifest is vendored into git and served from this repo.

**No patches applied** — unlike `platform/substrate/vendor/` (which needed real edits), this is a
verbatim copy. Keep it that way; if a change ever becomes necessary, document it here the way
`substrate/vendor/PATCH.md` does and mark edits inline with `ARIA-PATCH`.

## Upstream sync

On a version bump: re-download the release manifest, diff it, replace this file, and update the
version + sha256 above. Check the CRD `versions[]` block still serves **`v1alpha1`** (see below)
before rolling it out.

## The compatibility fact this whole spike rests on

ARIA's kagent is pinned at **0.9.10**, whose controller requests `agents.x-k8s.io/`**`v1alpha1`**.
Agent Sandbox v0.5.4's `sandboxes.agents.x-k8s.io` CRD serves BOTH:

```
version=v1beta1   served=true  storage=true   deprecated=false
version=v1alpha1  served=true  storage=false  deprecated=true   # "use v1beta1" warning
```

`v1alpha1` is deprecated but **still served**, with a conversion webhook translating between them —
so kagent 0.9.10 works **unchanged**, no version bump, no beta, no risk to the live fleet. (This is
what makes agent-sandbox the lower-risk path vs. Agent Substrate, which stalled needing kagent
0.10.0-beta — see `platform/substrate/README.md`.)

**If a future agent-sandbox release drops `v1alpha1`, this breaks** until kagent is upgraded. Re-check
that CRD versions block on every bump — it's the load-bearing assumption.
