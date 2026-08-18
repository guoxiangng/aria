# Workstream — Agent Execution Environment

> **The single owner for how ARIA's agents are executed and isolated.** Supersedes the two separate
> spec docs (`spec-agent-substrate-integration.md`, `spec-agent-sandbox-integration.md`), which were
> written before we understood how the pieces relate — treat those as historical build notes.
>
> Last updated: 2026-08-18 · researched against kagent docs + upstream repos + the live cluster.

> ## Status (2026-08-18): both platforms INSTALL and RUN; neither's headline feature is PROVEN
>
> The kagent 0.9.10 → 0.10.0-rc1 upgrade shipped and both probes are genuinely `Ready: True` — real
> progress, see §10. But testing what each runtime actually promises (§11) came back negative on both:
> Substrate never suspended `substrate-probe` over 2+ days idle, and Agent Sandbox's network/kernel
> isolation for `agent-sandbox-probe` is accepted into the config but not enforced. Read §10 for the
> install/upgrade story, §11 for what the promises turned out to be. Full write-up:
> `../../articles/05-article-two-sandbox-runtimes.md` (private draft). §§7-9 are the pre-upgrade plan,
> kept for the record.

## 1. The corrected mental model

kagent runs an agent as a **plain Kubernetes Deployment** by default. Everything below is opt-in.

```
Agent            (kagent.dev)  → Deployment + Pod          ← the default, what ARIA's fleet runs
SandboxAgent     (kagent.dev)  → an isolated runtime, selected by spec.platform:
                                   ├─ substrate      → Agent Substrate   (ate.dev)
                                   └─ agent-sandbox  → Agent Sandbox     (agents.x-k8s.io)
AgentHarness     (kagent.dev)  → ALWAYS Agent Substrate. No platform choice.
```

Three CRDs are kagent's own. The **runtimes are not** — they are separate projects, shipped
separately, each with its own controller, namespace and API group. kagent contributes the
*abstraction*; the isolation belongs to whichever runtime you install.

## 2. The three projects, correctly attributed

This is where our earlier understanding was wrong — the names invite exactly the mix-up we made.

| | **kagent** | **Agent Substrate** | **Agent Sandbox** |
|---|---|---|---|
| API group | `kagent.dev` | `ate.dev` | `agents.x-k8s.io` |
| Repo | `kagent-dev/kagent` | **`agent-substrate/substrate`** | `kubernetes-sigs/agent-sandbox` |
| Governance | **CNCF** (Sandbox tier) | **Google-run.** Google CLA required; `ate-dev@googlegroups.com`; `GOVERNANCE.md` still *"Draft — not yet ratified"* | **Kubernetes SIG Apps** subproject |
| Traction | CNCF project | 1225★ · 229 forks · 350 open issues · active | k8s standards-track, v0.5.4 |
| Self-described maturity | 0.9/0.10 line | *"currently in early development… not ready for production use, and the APIs are almost guaranteed to change"* | pre-1.0 (`v1beta1` API) |
| In kagent's docs? | — | **Yes — a first-class core-concept page** | **Never mentioned** |
| Focus | agent lifecycle + routing | **density**: many actors multiplexed onto few workers; snapshot/resume | **isolation**: constraint profile, stable identity, warm pools |

**`agent-substrate` is a Google project, not a k8s-sigs one.** The k8s-sigs project is Agent
*Sandbox*. Both originate from Google, but took different governance paths: Sandbox went to SIG Apps
(standards track), Substrate stayed Google-run (Google CLA, draft governance, CNCF Slack only as a
chat venue).

### The asymmetry that matters for choosing

- kagent's `SandboxAgent` CRD **defaults to `agent-sandbox`**.
- kagent's **documentation only covers Substrate** — a dedicated core-concept page, and the Agents
  page states: *"A SandboxAgent runs on Agent Substrate: the kagent controller runs it as a
  gVisor-sandboxed actor instead of a Deployment."* Agent Sandbox appears nowhere in kagent's docs.
- **`AgentHarness` runs on Substrate exclusively** — *"Every `AgentHarness` runs on Agent Substrate."*

So the CRD default points one way and the documentation + harness dependency point the other. These
are not two interchangeable drivers behind one interface; they're two different bets.

## 3. Corrections to our prior understanding (things we had wrong)

| Prior belief | Reality |
|---|---|
| "Substrate is a nascent 4-star project" | We were looking at **`kagent-dev/substrate`, which is a *fork***. Upstream `agent-substrate/substrate` has **1225★, 229 forks, 350 open issues**, pushed within days. |
| "Substrate is a kagent-dev / Solo.io project" | It's a **Google** project. kagent-dev merely forks it (and ships it as an optional subchart). |
| "Substrate is built on top of Agent Sandbox's primitives" | **No.** Came from a second-hand blog summary. Substrate's README describes its own gVisor/microVM support and never references Agent Sandbox. They are **parallel**, not layered. |
| "Substrate is just an optional external backend" | kagent treats it as **first-class** — core-concept page, and the only runtime `AgentHarness` can use. |
| "We tore down Substrate to install Agent Sandbox" | Both are **installed and running side by side** right now. Only the temporary *manual Helm release* was removed (ArgoCD owns it now). |

## 4. AgentHarness — the piece we hadn't looked at

An `AgentHarness` provisions a **long-running remote execution environment for third-party coding
agents** — `spec.backend` is `openclaw` or `hermes`, both speaking **ACP** (Agent Client Protocol).
kagent generates a per-harness `ActorTemplate` and creates a shared actor on first chat connect.
Other fields: `spec.substrate` (WorkerPool + snapshot config), `spec.modelConfigRef`, `spec.image`,
`spec.channels` (e.g. Slack).

**Why it matters to this workstream:** it's the clearest case of Substrate being *native* rather than
optional — there is no non-Substrate path. It's also a different use case from ARIA's InfraOps fleet
(interactive coding agents, not autonomous diagnostics), so it is **out of scope for now** — but it
explains why kagent's docs lean Substrate.

## 5. Agent Memory (adjacent, mostly done)

Vector-backed long-term memory using **pgvector inside kagent's own Postgres** — not Pinecone, not a
separate database. Requires: `database.postgres.vectorEnabled: true`, a pgvector-capable image, an
embedding `ModelConfig`, and `spec.declarative.memory.modelConfig` on the agent (`ttlDays` defaults
to 15). Auto-extracts every 5th user message; retrieves by cosine similarity.

**ARIA status:** the Postgres side is already done in a parallel session (`vectorEnabled: true` +
`pgvector/pgvector:pg18` image + an embedding ModelConfig with its own ESO secret). Remaining: set
`memory` on one agent and exercise it. Tracked as a quick win, not part of this workstream.

## 6. Where ARIA actually is (live, 2026-08-15)

Both runtimes are **installed, healthy, and GitOps-managed**; neither can run an agent on kagent 0.9.10.

| | State |
|---|---|
| Agent Substrate (`ate-system`) | Control plane healthy ~11d. Vendored+patched chart (valkey 6→3), certs via TF→Secrets-Manager→ESO. `substrate` app reads `OutOfSync` (drift from the valkey work) but `Healthy`. |
| Agent Sandbox (`agent-sandbox-system`) | Controller + 4 CRDs healthy. Installed clean on stock EKS; fleet unaffected. `v1alpha1` compat with kagent 0.9.10 verified live. |
| `substrate-probe` | `Accepted: True`, never Ready — `golang-adk` image 404s (0.9.10 resolves the old registry). |
| `agent-sandbox-probe` | `Accepted: True`, never Ready — kagent reconciler bug: `Index with name field:.metadata.owner does not exist`. |
| Real wins banked | EKS node-SG bug found+fixed (cross-node privileged ports); gVisor confirmed on stock t3.large; full GitOps + ESO cert path proven. |

**Root cause of both failures:** `SandboxAgent` is a **0.10-line feature**. 0.9.10 shipped the API
without the machinery.

## 7. The unblock: kagent 0.9.10 → 0.10.0-rc1

Approved in principle; to be done deliberately after this doc. `rc1` is a **release candidate**, not a
beta, and it carries the fixes for both paths.

**What the upgrade touches** (full analysis: `../../articles/outline-lifecycle-layer.md`):
- Agent **definitions** are GitOps-owned → safe. CRD API versions unchanged → no conversion.
- Agent **runtime images** are re-imaged fleet-wide: the agent image tag defaults to the chart
  version, and the default registry moves `cr.kagent.dev` → `ghcr.io`. Expect a rolling restart of
  every declarative agent.
- **State**: the controller runs DB migrations on startup — assume **one-way**. Snapshot the Postgres
  PVC first. This is the only genuinely irreversible part.
- **BYO** (`investigation-loop`) keeps its own ECR image, but talks A2A to a new controller → test it.

**New decision the upgrade forces:** rc1 declares substrate as a **subchart** (`condition:
substrate.enabled`, `oci://ghcr.io/kagent-dev/substrate/helm`, version **0.0.9**). ARIA installs
Substrate as its own ArgoCD app from a *vendored, patched* 0.0.10 chart. Options:
- **(a) Keep ARIA's app; set `substrate.enabled: false`.** Preserves the valkey 6→3 patch and the
  ESO-cert wiring. Version pairing (kagent rc1 ↔ substrate 0.0.10) then needs checking — community
  guides pin *pairs* because the ateapi protos move.
- **(b) Adopt the subchart.** Version pairing handled upstream; loses the valkey patch (back to 6
  pods) and the ESO-cert arrangement would need re-doing.
- Recommended: **(a)**, then re-evaluate once Substrate stabilises.

## 8. Open questions to resolve before/during the retry

1. **Does 0.10.0-rc1 fix the agent-sandbox field-index bug?** Unverified — we only know Substrate's
   fix (`goAgentImage`) is present. Check after upgrading; it determines whether *both* paths work.
2. **Substrate version pairing** with rc1: does 0.10.0-rc1 work against our 0.0.10, or must we match
   the 0.0.9 it bundles?
3. ~~**Do the `ghcr.io` images pull anonymously** from the EKS nodes?~~ **RESOLVED 2026-08-15: yes.**
   Verified with a disposable, self-cleaning `Job` (`activeDeadlineSeconds: 60`, deleted after) pulling
   `ghcr.io/kagent-dev/kagent/app:0.10.0-rc1` in the `kagent` namespace. Kubelet event confirmed the
   pull explicitly: `Pulled ... image already present on machine and can be accessed by the pod`. (The
   job's own exit code 128 was a red herring — the probe command `true` doesn't exist in this
   distroless-style image; irrelevant to the pull question.) Not a rollout blocker.
4. **Which runtime does ARIA actually standardise on?** Not urgent, but the article needs a position:
   Substrate (density, kagent-native, harness-capable, Google-governed, pre-production) vs Agent
   Sandbox (isolation, standards-track, portable, not in kagent's docs). Running both indefinitely is
   a lab luxury, not a platform decision.
5. **Is the valkey patch still needed** on whatever Substrate version we land on — and is it still
   absent upstream? (Feeds the OSS thread; note the PR target is **upstream**, not the fork.)

## 9. Retry plan (sequenced)

1. **Pre-flight**: ~~snapshot the kagent Postgres PVC~~ **done 2026-08-15** — EBS snapshot
   `snap-031377c9cffb8a417` of `vol-0431ebbab83214108` (the `kagent-postgresql` PVC's backing volume),
   tagged `kagent-postgresql-pre-0.10-upgrade`. This is the rollback point if the DB migration on
   upgrade goes wrong — restore a new volume from this snapshot and re-point the PVC. ~~verify
   anonymous `ghcr.io` pulls from a node~~ **done, see open question #3**; confirm no in-flight
   agent work (still outstanding — check before starting the upgrade itself).
2. **Upgrade** `gitops/apps/kagent.yaml` + `kagent-crds` → `0.10.0-rc1` (CRDs first, existing wave
   order handles it). Set `substrate.enabled: false` per §7(a). Watch the controller roll.
3. **Verify the fleet first, before touching probes** — all existing agents `Ready`, `investigation-loop`
   (BYO/A2A) answering. This is the blast-radius check; stop and roll back planning here if it fails.
4. **Retry `substrate-probe`** — expect the `goAgentImage` override to resolve the 404. Set
   `controller.goAgentImage.registry: ghcr.io` if not defaulted.
5. **Retry `agent-sandbox-probe`** — tests open question #1.
6. **Measure what the spikes were for**: suspend/resume + real resume latency (Substrate); isolation
   behaviour + warm pools (Agent Sandbox). This is the article payload that's still missing.
7. **Update**: this doc → `_STATUS.md` → `build-in-public-plan.md` (#5), per the status-ownership rule.

## 10. The upgrade, executed — full account (2026-08-16)

### Pre-flight
- `ghcr.io` pull confirmed working (disposable self-cleaning Job; kubelet `Pulled` event).
- Postgres PVC snapshotted: `snap-031377c9cffb8a417` of `vol-0431ebbab83214108` — the rollback point.
- In-flight-work check surfaced an **unrelated concurrent thread**: a `github` MCPServer mid-setup
  (`SecretSyncedError` on `github-pat`, harmlessly crashlooping 9h+). Confirmed orthogonal to the
  kagent version (kmcp stays 0.3.0 either way) and left untouched — not this workstream's to fix.

### Upgrade
`gitops/apps/kagent-crds.yaml` + `kagent.yaml` → `0.10.0-rc1`, validated locally (`helm template`
against our values, both charts render clean, substrate subchart confirmed still `condition: false`
so our vendored app stays authoritative — only RBAC + the `WorkerPool` CR render from it). Pushed;
ArgoCD synced both apps `Synced/Healthy`. Controller rolled `1/1 Running`, 0 restarts. **Postgres pod
untouched, no restart** — no migration crash.

### Fleet verification gate — passed clean
All 10 declarative/BYO agents `Ready: True`; pods cycled to new images exactly as the lifecycle
analysis (§ outline-lifecycle-layer.md) predicted — Python agents → `ghcr.io/.../app:0.10.0-rc1`,
Go agents → `ghcr.io/.../golang-adk:0.10.0-rc1`. **`investigation-loop` (BYO) kept its own ECR image
unchanged**, confirmed live evidence for the definition/runtime split: it answered the *new*
controller's A2A discovery calls (`GET /.well-known/agent-card.json` → `200 OK` repeatedly) without
being rebuilt or redeployed itself.

### Retrying the probes — three real problems, each diagnosed and fixed in turn

**1. `substrate-probe`: stale `ActorTemplate`, cached before the upgrade.** kagent's controller only
regenerates a SandboxAgent's `ActorTemplate` when the *SandboxAgent spec* changes — it wasn't watching
for the registry move, which came from the chart version bump, so the original `ActorTemplate` (with
the dead `cr.kagent.dev/.../golang-adk` reference) sat untouched. The controller quietly created a
**second**, correctly-imaged `ActorTemplate` (`substrate-probe-<hash>`) alongside it, but the live
`Sandbox`/pod stayed pinned to the first. Fix: delete the stuck `Sandbox` (safe — `SandboxAgent` CR
unchanged, nothing stateful to lose on a spike probe) so it regenerates from the current template.
**Lesson for the OSS thread:** kagent doesn't garbage-collect a superseded `ActorTemplate` when it
regenerates one — see step 3 below, this bit twice.

**2. Real capacity constraint discovered: `platform: substrate` and `platform: agent-sandbox` actors
share ONE `WorkerPool`.** This was not previously known and corrects an assumption in §§1-6 above —
we'd treated the two platforms as fully separate capacity pools. In fact `ate-controller` manages
`ActorTemplate`s for *both* platform selectors identically; `agent-sandbox-probe`'s actor (already
running 3 days) occupied the lab's only worker (`WorkerPool.replicas: 1`), so `substrate-probe`'s
resume failed with `no free workers available` even after fix #1 landed. Fix: bumped
`substrateWorkerPool.replicas` 1→2 in `platform/kagent/values.yaml`, GitOps-committed. Pod-slot
headroom was checked first (tight: ~30-32/35 per node, other concurrent threads also consuming
capacity) — flagged inline in the values comment for whoever touches this next.

**3. The dangling orphan.** Even after fix #1's replacement `ActorTemplate` existed, `ate-controller`
kept retrying the **original, stale** one every ~4 minutes (still owned by the same `SandboxAgent`,
never cleaned up). It cost real debugging time before the pattern was obvious. Fix: delete the stale,
unsuffixed `ActorTemplate substrate-probe` directly (confirmed safe: same owner UID as the fresh one,
clearly superseded). This is the same finding as #1's lesson, worth one upstream issue rather than two.

### Result
```
$ kubectl get sandboxagent -n kagent
NAME                  READY   ACCEPTED
agent-sandbox-probe   False   ← see caveat below
substrate-probe       True    True
```
`substrate-probe`: `Ready: True`, `"ActorTemplate golden snapshot is ready"`. Genuinely working — the
Substrate density model in action: no Pod named `substrate-probe` exists at all; it's an actor
multiplexed inside a shared `kagent-default-*` worker pod, which is the entire point of the runtime.

**Caveat on `agent-sandbox-probe`'s `READY: False`:** the underlying `Sandbox` object shows
`READY: True, DependenciesReady`, and its pod has been `Running` and answering A2A discovery calls for
3+ days straight — the live serving path is fine. The top-level `SandboxAgent.status.Ready` flickers
False because *golden-snapshot/warm-standby maintenance* (a background process distinct from the live
pod) loses the worker-contention race intermittently. **A misleading status signal, not an outage** —
worth knowing before assuming `Ready: False` means the agent is down. Could resolve by bumping
`WorkerPool.replicas` to 3, at the cost of more pod-slots on an already-tight lab; not urgent.

### What's actually still open
- Open questions §8 #2 (substrate version pairing with rc1) and #5 (valkey patch still needed
  upstream) — unaffected by this session, still open.
- Open question §8 #1 (does rc1 fix the field-index bug) is **superseded** — the actual failure mode
  turned out to be the ActorTemplate staleness/WorkerPool sharing above, not the old
  `.metadata.owner` index bug, which didn't recur.
- The `github` MCPServer setup (unrelated concurrent thread) is still broken — not this workstream's
  concern, noted for whoever owns it.

## 11. Phase 4 — testing the actual headline promises (2026-08-16 → 2026-08-18)

With both probes `Ready`, we tested what each runtime is actually *for*, not just whether it installs.
Full narrative + evidence: `../../articles/05-article-two-sandbox-runtimes.md` (private draft) — this
section is the canonical technical record; that draft is the write-up.

**Substrate: suspend/resume never observed.** `substrate-probe` was left genuinely idle (no calls, no
polling) and its `ActorTemplate` status polled periodically: `Ready` at resume (`04:21:28Z`), `Ready`
at ~21 min idle, `Ready` at ~2h idle, **`Ready` at ~2 DAYS idle** (`2026-08-18T13:22:11Z`). It never
suspended once. No configurable idle-timeout was found exposed in the chart's values or templates —
likely hardcoded in the `ate-api`/`ate-controller` binaries, or the mechanism doesn't fire in this
deployment shape. Stated as an observation, not a verdict — Substrate is explicitly pre-production and
this is a single-actor, single-cluster sample.

**Agent Sandbox: neither isolation lever is actually enforced.**
- **Network**: `spec.sandbox.network.allowedDomains` is genuinely applied to the live `Sandbox` object
  (confirmed in its spec), but a live test reaching a non-allow-listed domain (`example.com`) from
  inside the pod **succeeded** — nothing blocks it. Checked and ruled out the obvious alternative
  explanation (Istio, separately installed on this cluster for identity/authz by other work): mesh
  `outboundTrafficPolicy` is left at Istio's own permissive default (`ALLOW_ANY`), and no
  `AuthorizationPolicy` exists for this agent — and that resource type governs inbound traffic to a
  workload, not its own outbound egress, so it's the wrong mechanism regardless.
- **Kernel isolation**: `kubectl get runtimeclass` returns nothing — no `RuntimeClass` exists on the
  cluster at all. Neither the vendored agent-sandbox manifest nor our `SandboxAgent` spec provisions
  one; getting gVisor/Kata active needs node-level runtime-handler installation, genuine infra work
  outside what either project's own manifest can bring. The agent runs on the plain default
  container runtime today, not a sandboxed one.

**Correction to earlier documentation:** `platform/agent-sandbox/README.md`'s "secure by default"
section (written 2026-08-07) stated the network-deny behaviour as verified. It wasn't — that was
inferred from the CRD field's description text, never live-tested until this session. Corrected in
that README; noted here as a reminder to distinguish "the schema says X" from "X is true."

**What this changes:** both control planes install cleanly and both agents reach a genuinely stable
`Ready` state and answer real requests through kagent's controller — that part is solid and real. But
neither runtime's own headline feature (density-via-suspend for Substrate; isolation-via-policy for
Agent Sandbox) was observed working on this deployment, at these versions. That became the article's
actual spine rather than a "here are the benchmark numbers" piece — see the draft for the full
treatment.

## Related
- `../platform/substrate/README.md`, `../platform/agent-sandbox/README.md` — component detail.
- `../../articles/outline-lifecycle-layer.md` — the upgrade's blast-radius analysis (article #9) —
  **now largely CONFIRMED by §10's live evidence**, not just predicted from chart values.
- `../../articles/outline-sandbox-layer.md` — article #5; §10 is now the payload for it.
- `../../articles/oss-contributions.md` — upstream threads (note: PR target is `agent-substrate/substrate`).
  **Add**: stale-`ActorTemplate`-not-garbage-collected-on-regeneration (§10 fixes #1/#3).
- `spec-agent-substrate-integration.md`, `spec-agent-sandbox-integration.md` — superseded build specs.
