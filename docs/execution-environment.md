# Workstream — Agent Execution Environment

> **The single owner for how ARIA's agents are executed and isolated.** Supersedes the two separate
> spec docs (`spec-agent-substrate-integration.md`, `spec-agent-sandbox-integration.md`), which were
> written before we understood how the pieces relate — treat those as historical build notes.
>
> Last updated: 2026-08-15 · researched against kagent docs + upstream repos + the live cluster.

---

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

## Related
- `../platform/substrate/README.md`, `../platform/agent-sandbox/README.md` — component detail.
- `../../articles/outline-lifecycle-layer.md` — the upgrade's blast-radius analysis (article #9).
- `../../articles/oss-contributions.md` — upstream threads (note: PR target is `agent-substrate/substrate`).
- `spec-agent-substrate-integration.md`, `spec-agent-sandbox-integration.md` — superseded build specs.
