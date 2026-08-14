# Agent Sandbox on ARIA (EKS)

[kubernetes-sigs/agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox) is a **Kubernetes
SIG Apps subproject** providing a `Sandbox` CRD + controller for isolated, stateful, singleton
workloads — purpose-built for AI agent runtimes. Isolation is delegated to a secure runtime
(gVisor / Kata) via `RuntimeClass`; sandboxes get a stable network identity and optional persistent
storage.

It is **not** the layer Agent Substrate is built on — an earlier version of this doc said so, based on a
second-hand blog summary; corrected 2026-08-15. The two are **parallel** projects, both Google-originated
but on different governance tracks: Agent Sandbox went to Kubernetes SIG Apps (standards track), while
Agent Substrate stayed Google-run (`agent-substrate/substrate`, Google CLA). Substrate implements its own
gVisor/microVM isolation and never references Agent Sandbox. Where Substrate optimises for *density*
(many actors multiplexed onto few workers, snapshot/resume), Sandbox optimises for *isolation and
lifecycle*. See `../../docs/execution-environment.md` for the full comparison.

## Why this, and why it's the lower-risk path

ARIA's Substrate spike (`../substrate/README.md`) got the control plane fully working on EKS but
stalled: its Go actor-runtime image is only published where kagent **0.10.0-beta** looks, and bumping
the shared kagent chart to a beta would risk the live fleet (`cluster-diagnostics`,
`incident-commander`, `investigation-loop`) for the sake of one spike. Rejected.

Agent Sandbox sidesteps that entirely — **two verified facts**:

1. **No kagent version bump.** kagent 0.9.10 requests `agents.x-k8s.io/v1alpha1`; agent-sandbox
   v0.5.4 still **serves** it (deprecated, alongside `v1beta1`, with a conversion webhook). Verified
   directly from the release manifest — see `vendor/PROVENANCE.md`. kagent's CRD does default
   `platform` to `agent-sandbox` — **but note the asymmetry** (found 2026-08-15): kagent's *documentation*
   covers only Agent Substrate (a core-concept page; `AgentHarness` runs on Substrate exclusively) and
   never mentions Agent Sandbox. The default points one way, the docs the other — so "primary path" is
   true of the CRD default only, not of kagent's documented direction. See `../../docs/execution-environment.md`.
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

## Status — deployed; probe blocked by a kagent 0.9.10 bug (2026-08-07)

**Deployed and healthy:** ArgoCD app `Synced/Healthy`, controller `1/1 Running`, all 4 CRDs
installed, `v1alpha1 served=true` confirmed live. No EKS-specific problems at all — it installed
cleanly on stock EKS (unlike Substrate, which needed a node-SG fix). The live fleet was unaffected
(all agents stayed `Ready`), confirming the CRD install didn't destabilize the shared controller.

**The compatibility premise was validated.** kagent 0.9.10 successfully reached the v1alpha1 API
through the conversion webhook — the controller logged the upstream deprecation warning
(`agents.x-k8s.io/v1alpha1 Sandbox is deprecated; use v1beta1`), proving the call landed. The
earlier `no matches for kind "SandboxList"` error is gone.

**But the probe fails one layer deeper, inside kagent's own reconciler:**

```
error listing *v1alpha1.Sandbox: Index with name field:.metadata.owner does not exist
```

kagent 0.9.10 queries its controller-runtime cache using a field index it never registered — a bug
in the kagent binary, not fixable from config. No public issue filed upstream.

### Conclusion: kagent 0.9.10 cannot run `SandboxAgent` on EITHER platform

| platform | blocker on kagent 0.9.10 |
|---|---|
| `substrate` | `golang-adk` runtime image 404 at 0.9.10's registry path |
| `agent-sandbox` | unregistered `.metadata.owner` field index (above) |

Both are the same underlying story: **SandboxAgent is a 0.10-line feature.** The release notes make
this explicit — 0.9.10 shipped only the skeleton (*"add substrate as a subchart"*, *"degrade
gracefully when ate.dev CRDs are absent"*), while the actual functionality landed across
0.10.0-beta1→rc1 (*"substrate support for BYO and python runtimes for SandboxAgent"*, *"gate
SandboxAgent actor readiness"*, *"store session state for declarative sandbox agents"*).

**`v0.10.0-rc1` now exists** (chart published 2026-07-29) — a *release candidate*, materially further
along than the beta11 that was evaluated and rejected earlier, and it carries the `goAgentImage`
override that unblocks Substrate too. It bundles substrate `0.0.9` as a subchart (note: ARIA
currently runs substrate `0.0.10` standalone — version pairing between kagent and substrate has
mattered historically, so align them deliberately if upgrading).

Upgrading kagent is therefore the single change that would unblock **both** spikes — but it upgrades
the controller serving the live fleet, so it's a deliberate decision, not a side effect of this work.
Left un-upgraded here.
