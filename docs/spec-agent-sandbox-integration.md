# Spec — Agent Sandbox integration (spike, not a Substrate replacement)

> Written to be handed to a fresh conversation with no prior context. If you're that conversation:
> read this whole doc before touching the cluster. Where it says "VERIFY," do not proceed past that
> step until you've confirmed the fact live — Agent Sandbox is pre-1.0 and moving; several claims
> below come from web research in Aug 2026.

## 1. What this is and why

**ARIA** is a governed multi-agent InfraOps platform on Amazon EKS, built on
[kagent](https://kagent.dev) (`ap-southeast-1`, cluster `aria`). See `docs/repo-structure.md` for
layout and `docs/deploy-layers.md` for the deploy-layer law (Terraform=AWS only, ArgoCD=all K8s).

**Why this, now:** the Agent Substrate spike (`spec-agent-substrate-integration.md`, see
`platform/substrate/README.md` for the full outcome) got the control plane fully working on EKS
(found + fixed a real EKS node-security-group bug along the way) but stalled on its last step: the
Go actor-runtime image (`golang-adk`) is only published at the registry path kagent **0.10.0-beta**
knows to use, not kagent 0.9.10 (ARIA's pinned version, running the live fleet). Bumping the shared
kagent chart to a beta to unblock one spike was rejected — it would risk
`cluster-diagnostics`/`incident-commander`/`investigation-loop`, not just this experiment.

**[kubernetes-sigs/agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox)** is the
project Substrate is actually built on top of: a formal **Kubernetes SIG Apps** subproject (Google
Open Source Blog, Nov 2025; launched at KubeCon Atlanta), providing a `Sandbox` CRD + controller for
isolated, stateful, singleton workloads (gVisor/Kata runtime, stable identity, persistent storage).
Substrate takes Sandbox's isolation/snapshotting primitives and adds a density-focused control plane
on top; Sandbox itself is the more foundational, more formally-governed piece underneath.

**The practical reason this is worth trying instead of forcing Substrate further:** kagent's
`SandboxAgent` CRD already exposes `spec.platform: enum: [agent-sandbox, substrate]` — confirmed
live against ARIA's CURRENT kagent 0.9.10 (`kubectl explain sandboxagent.spec.platform`). Unlike
Substrate, trying `platform: agent-sandbox` needs **no kagent version bump** — it's a value the
already-pinned 0.9.10 controller understands. That directly avoids the exact risk (beta-on-the-shared-fleet)
that stalled Substrate.

**Storyline for build-in-public content (per user's framing):** Substrate's version-immaturity was a
genuine, honest blocker → rather than force a beta onto the live fleet, dropped down to the more
foundational, formally-governed primitive Substrate itself is built on. Same "isolation/sandboxing"
theme, different maturity/governance profile, no fleet risk.

## 2. Goal (scope this narrowly — mirrors the Substrate spike's discipline)

Stand up the **agent-sandbox controller** on ARIA's EKS cluster and get **one isolated agent**
running via `SandboxAgent` with `platform: agent-sandbox`, proving:
1. The agent-sandbox CRDs + controller install and come up on EKS (no EKS-specific docs exist
   upstream — same "nobody's documented this" gap Substrate had).
2. kagent 0.9.10, UNCHANGED, can actually drive a `platform: agent-sandbox` SandboxAgent end to end
   (this is the load-bearing unknown — see §5.1, check this FIRST, cheaply, before the full install).
3. The agent is reachable and answers via its A2A endpoint, running inside the sandbox's isolation
   boundary (gVisor or Kata, per whatever RuntimeClass is configured).

## 3. Explicit non-goals — do NOT do these

- **Do not migrate the existing fleet** onto agent-sandbox. Additive, isolated spike only —
  `cluster-diagnostics`, `incident-commander`, `investigation-loop` stay exactly as they are.
- **Do not touch `platform/substrate/` or re-attempt the golang-adk registry fix.** That's parked,
  documented, orthogonal. This is a different project, not a retry.
- **Do not bump kagent version for this.** The entire point of trying agent-sandbox first is that it
  might not require one. If step §5.1 shows kagent 0.9.10 genuinely can't drive it either (API version
  mismatch — see below), STOP and document that finding rather than bumping kagent to force it — same
  discipline as the Substrate decision.
- **Do not attempt Substrate + Agent Sandbox side by side in the same pass.** One project at a time.

## 4. THE key unknown — check this FIRST, before installing anything else (§5.1)

Confirmed live, ARIA's kagent 0.9.10 controller, from an earlier `platform: substrate` reconcile
attempt that incidentally touched this code path:

```
error listing *v1alpha1.SandboxList: failed to get restmapping: no matches for kind "SandboxList"
in version "agents.x-k8s.io/v1alpha1"
```

kagent 0.9.10 is asking for `agents.x-k8s.io/v1alpha1`. Agent Sandbox's current released CRDs
(per its README, researched Aug 2026) are `agents.x-k8s.io/v1beta1` — a newer API version. This is
**structurally the same failure mode that stalled Substrate**: ARIA's pinned kagent version expecting
something older than what the upstream project now ships. It may turn out fine (v1alpha1 CRDs might
still be installed alongside v1beta1 for back-compat, or kagent may accept either) — or it may be an
immediate, cheap dead-end. **Resolve this before doing anything else in this spec.**

## 5. Prerequisites / VERIFY-first checklist

Do these, in order:

1. **THE compatibility check (do this before any full install).** Install ONLY the agent-sandbox
   CRDs (not the controller) from the current release, and check: does `agents.x-k8s.io/v1alpha1`
   exist (either as the actual served version, or via a conversion webhook / stored version kagent
   can hit)? `kubectl api-resources | grep agents.x-k8s.io` and `kubectl get crd sandboxes.agents.x-k8s.io -o yaml`
   (check `.spec.versions[]`). If v1alpha1 is nowhere in the served versions, this is very likely a
   dead end for kagent 0.9.10 — STOP, document it as the finding (a second, cleaner "version drift
   between two co-evolving projects" story), and don't force it.
2. **Current agent-sandbox release** — check `https://github.com/kubernetes-sigs/agent-sandbox/releases`
   for the latest tag at build time (this doc's research saw a `0.x` series, pre-1.0, `v1beta1` API —
   VERIFY, do not trust this doc's version number).
3. **Install method** — `kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/<VERSION>/sandbox-with-extensions.yaml`
   per the upstream README (no Helm chart as of this research — VERIFY still true; if a Helm chart
   now exists, prefer it to match ARIA's GitOps pattern, see `docs/deploy-layers.md`).
4. **Runtime class** — Agent Sandbox delegates isolation to gVisor or Kata via `RuntimeClass`,
   described as optional/pluggable. Substrate's spike already proved **gVisor runs cleanly on ARIA's
   stock EKS t3.large nodes** (no custom AMI, no node bootstrap changes) — reuse that finding; gVisor
   is the lower-risk choice here too, avoid Kata unless gVisor doesn't fit.
5. **Resource footprint** — upstream docs didn't specify this (VERIFY live once installed: `kubectl
   get pods -n <agent-sandbox-namespace>` + `kubectl top`). ARIA's 2× t3.large lab is already tight
   (Substrate's spike found the VPC-CNI 35-pod-per-node limit binding, not CPU) — check pod count
   before assuming headroom.
6. **Model provider** — same recommendation as the Substrate spec: use the existing Azure OpenAI
   `default-model-config`, don't introduce a new variable.

## 6. GitOps / commit hygiene (match existing repo conventions — see `docs/deploy-layers.md`)

- Per the layering law: this is Kubernetes-only (CRDs + controller + a SandboxAgent CR) — **no
  Terraform**, all ArgoCD-managed. If the compatibility check (§5.1) fails immediately, don't even
  wire GitOps for it — note the finding in this doc / `platform/substrate/README.md`'s sibling and stop.
- If it proceeds: CRDs + controller under a new `platform/agent-sandbox/` (mirror
  `platform/substrate/`'s structure — README + values/manifests), a new `gitops/apps/agent-sandbox*.yaml`
  (wave 0, same pattern as `substrate-crds`/`substrate-config`), and a test agent under
  `agents/agent-sandbox-probe/` (NOT reusing `agents/substrate-probe/` — keep them distinct, both stay
  as documented reference points).
- Standard repo rule: verify facts live before asserting versions in docs — this project has been
  burned twice now (Substrate chart version, then the golang-adk registry) by stale assumptions.

## 7. If it doesn't work — document the failure, don't force it

If §5.1's compatibility check fails cleanly and early, that IS the finding — and arguably a *better*
one than Substrate's for the article: two Kubernetes-native agent-sandboxing projects, co-evolving
independently, drift out of API-version sync with the very controller (kagent) meant to unify them.
Write it up plainly. Do not bump kagent to force compatibility — that repeats the exact tradeoff
already rejected for Substrate.

## 8. Downstream use

Feeds the same article/post thread as the Substrate spike (`../../articles/` — gitignored, private
tracking) — likely as a short, honest "tried the more foundational layer instead, here's what I found"
follow-up rather than a full separate article, unless §5.1 turns up something substantial.
