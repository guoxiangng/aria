# Agent Sandbox on ARIA (EKS)

[kubernetes-sigs/agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox) is a **Kubernetes
SIG Apps subproject** providing a `Sandbox` CRD + controller for isolated, stateful, singleton
workloads — purpose-built for AI agent runtimes. Isolation is delegated to a secure runtime
(gVisor / Kata) via `RuntimeClass`; sandboxes get a stable network identity and optional persistent
storage.

It's the **foundational layer Agent Substrate is built on**: Substrate takes Sandbox's
isolation/snapshotting primitives and adds a density-oriented control plane over them. Where
Substrate optimizes for *density* (suspend/resume, many actors per worker), Sandbox optimizes for
*isolation and lifecycle*.

## Why this, and why it's the lower-risk path

ARIA's Substrate spike (`../substrate/README.md`) got the control plane fully working on EKS but
stalled: its Go actor-runtime image is only published where kagent **0.10.0-beta** looks, and bumping
the shared kagent chart to a beta would risk the live fleet (`cluster-diagnostics`,
`incident-commander`, `investigation-loop`) for the sake of one spike. Rejected.

Agent Sandbox sidesteps that entirely — **two verified facts**:

1. **No kagent version bump.** kagent 0.9.10 requests `agents.x-k8s.io/v1alpha1`; agent-sandbox
   v0.5.4 still **serves** it (deprecated, alongside `v1beta1`, with a conversion webhook). Verified
   directly from the release manifest — see `vendor/PROVENANCE.md`. kagent's own CRD also documents
   `platform` as *"Defaults to agent-sandbox"*, so this is the primary path, not a side-branch.
2. **The missing image isn't in the way.** The substrate probe died pulling `golang-adk` (404 at
   kagent 0.9.10's registry path). Substrate only supports `runtime: go`. Agent Sandbox also supports
   **`runtime: python`** (kagent's default), which resolves to the `kagent/app` image — verified
   published (401 = exists). So `agent-sandbox-probe` uses `python` deliberately.

## Deploy model — fully ArgoCD-managed (per `docs/deploy-layers.md`)

| App | Wave | What |
|-----|------|------|
| `agent-sandbox` (`gitops/apps/agent-sandbox.yaml`) | 0 | CRDs + controller (vendored upstream manifest) |
| `agent-sandbox-probe` (`agents/`) | 5 | the probe SandboxAgent (`platform: agent-sandbox`) |

No Terraform — this is Kubernetes-only, so it's entirely platform-layer. No manual `kubectl apply`.

### Vendored manifest (`vendor/`)

Upstream ships a plain `kubectl apply -f <github-release-URL>`, **no Helm chart**. ArgoCD can't
source a remote URL, so the manifest is vendored **unmodified** into git (no patches, unlike
`../substrate/vendor/`). Source URL, version, and sha256 are recorded in `vendor/PROVENANCE.md`.

### The one ArgoCD gotcha handled up front

The controller **self-signs its webhook certs at runtime**: it creates the
`agent-sandbox-webhook-certs` Secret and **patches each CRD's `conversion.webhook.clientConfig.caBundle`**
(which ships empty). With `selfHeal: true`, ArgoCD would revert that injected caBundle every sync —
breaking the conversion webhook, and with it the `v1alpha1` support kagent 0.9.10 depends on. The
Application therefore carries an `ignoreDifferences` entry for exactly that field (and nothing else).

No cert-manager dependency and no Helm `lookup` problem here — a cleaner GitOps story than Substrate's.

## Secure-by-default networking (expect this to bite)

Agent Sandbox denies outbound network access unless explicitly allow-listed
(`spec.sandbox.network.allowedDomains` on the SandboxAgent). A sandboxed agent with no allow-list
**cannot reach its LLM provider** — that's the isolation boundary working, not a bug.
`agent-sandbox-probe` allow-lists the Azure OpenAI endpoint from `platform/kagent/values.yaml`.

This is the most interesting governance property of the project for ARIA's thesis: per-agent,
declarative egress control living next to the agent definition.

## Verify

```bash
kubectl get pods -n agent-sandbox-system                  # controller Running
kubectl get crd | grep agents.x-k8s.io                    # 4 CRDs
kubectl get crd sandboxes.agents.x-k8s.io \
  -o jsonpath='{range .spec.versions[*]}{.name}{" served="}{.served}{"\n"}{end}'   # v1alpha1 MUST be served
kubectl get sandboxagent agent-sandbox-probe -n kagent    # Accepted / Ready
kubectl get sandbox -A                                    # the actual Sandbox the agent runs in
```

## Status

Codified and validated locally; not yet rolled out at time of writing. Update this section with the
live outcome (and any EKS-specific findings — there are no EKS-specific upstream docs, same gap
Substrate had) once it's applied.
