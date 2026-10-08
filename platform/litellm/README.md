# platform/litellm — model gateway (domain 10)

> **Doc version: v3 · Last updated: 2026-09-26 · Status: live, verified · Stateful**
> Supersedes v2.2 (`_archive/README.v2.2026-09-24.md`) and v1 (`_archive/README.v1.2026-09-04.md`).
> Versioning rule for this doc: bump the version and archive a snapshot when the component's *shape*
> changes (a provider swapped, a consumer added fleet-wide). Routine status edits just move the date.

ARIA's model gateway: a self-hosted [LiteLLM](https://docs.litellm.ai/) proxy that the declarative
agents call instead of talking to a model provider directly. Fills what `aria/docs/ARCHITECTURE.md` §2 once listed
as `❌ not built`, and is the first real build under `LADP/docs/direction-2-llm-gateway-observability.md`.

**As of 2026-09-24 this is the declarative fleet's model plane.** **All 11 declarative agents route through it** — 7 of ARIA's own via `litellm-gateway`, plus kagent's
4 chart-managed built-ins via `default-model-config`, which the chart now generates as an OpenAI
provider pointed at this proxy. Of the 2 BYO agents, `investigation-loop` **does** (since 2026-09-26, via the Azure-compatible
route, allow-listed) and `strands-investigator` does **not** — it calls Bedrock directly via Pod Identity
and is not on the mesh allow-list (verified live 2026-10-03). That was not the original
plan — v1 deliberately wired up one agent — see "The Azure removal" below.

⚠️ Corrected 2026-09-24: this section previously claimed "all 9 agents". That was wrong, and wrong in a
way worth recording — the four chart-managed built-ins take their model from `default-model-config`, not
from anything in `agents/`, so the 2026-09-18 migration missed them entirely and they sat broken on the
dead Azure config for six days, all four reporting `Ready=True`. Caught by fact-checking an article
claim against the cluster, not by any alert.

## What runs here

| Route | Model | Role |
|---|---|---|
| `nova-micro` | `apac.amazon.nova-micro-v1:0` | cheapest route here ($0.037/1M in); fallback floor |
| `nova-lite` | `apac.amazon.nova-lite-v1:0` | **SIMPLE tier** ($0.063/1M in) — ~4x cheaper than haiku-3 |
| `nova-pro` | `apac.amazon.nova-pro-v1:0` | cross-family fallback for the fleet's own tier ($0.84/1M in) |
| `bedrock-haiku-3` | `apac.anthropic.claude-3-haiku-20240307-v1:0` | the router's classifier model ($0.25/1M in) |
| `bedrock-haiku-4-5` | `global.anthropic.claude-haiku-4-5-20251001-v1:0` | MEDIUM tier ($1); also what `litellm-gateway` serves |
| `bedrock-sonnet-5` | `global.anthropic.claude-sonnet-5` | COMPLEX tier ($2) |
| `bedrock-opus-5` | `global.anthropic.claude-opus-5` | REASONING tier ($5) |
| `cohere-embed-v4` | `global.cohere.embed-v4:0` | Embeddings for long-term memory (domain 8) |
| `smart-router` | — | Complexity Auto Router; picks one of the four tiers per request |

Two kagent `ModelConfig`s consume it, both `provider: OpenAI` pointed at
`http://litellm.litellm.svc.cluster.local:4000/v1`:
`litellm-gateway` (fixed model, what ARIA's own agents use; the 4 built-ins arrive via
`default-model-config`, which the kagent chart now generates as an OpenAI provider pointed here) and `litellm-smart-router` (the router, not yet
wired to any agent). `litellm-embedding` covers the embedding path.

## What this build closed (2026-09-26)

The Azure removal accidentally answered what a gateway is *for*: not routing, but containing the blast
radius of a provider vanishing, a key leaking, or a classifier going haywire — in one place. Three holes
this platform actually fell into, and what each now looks like:

**1. Budgets that enforce.** Caps are configured per deployment (`max_budget` + `budget_duration`).
Measured before and after, because the "before" is the interesting half:

| | Result |
|---|---|
| **Without a database** | `$0.000001/day` cap, 4 calls, **none blocked**. Same outcome for `router_settings.provider_budget_config` and for `rpm: 1`. Every shape accepted the config and enforced nothing. |
| **With Postgres** | call 1 answered, calls 2-4 **HTTP 429** — `No deployments available - crossed budget: Exceeded budget for deployment model_name: nova-micro ... 4.662e-06` |

Upstream says so plainly, in `proxy_server.py::_warn_budget_without_db`: *"the budget will NOT be
enforced and requests will never be blocked. Set DATABASE_URL"*. A config key being accepted is not the
same as a control existing — and nothing in the DB-less state hinted otherwise.

**2. Fallbacks.** Every tier has a fallback chain (`router_settings.fallbacks`), and four of the six
cross to a *different model family* on the first hop — including the fleet's own tier
(`haiku-4-5 → nova-pro`). Two stay in-family on purpose: `opus-5 → sonnet-5` and `nova-micro → nova-lite`. Proven with a kill test rather than asserted: a route pointed at a
deliberately non-existent Bedrock profile — standing in for Azure on 18 Sept — was **served by
`nova-micro` instead of failing**. Had this existed then, that outage would have been a quality
degradation, not six days of four dead agents and seven broken ones.

Fallbacks also make the new caps safe: a tier that hits its daily budget is filtered out of the pool and
a fallback catches the request, instead of the caller seeing a 429.

**3. A real cheap floor.** Amazon Nova joins Anthropic — a second *family*, not just more models, which
is what gives fallbacks somewhere to go that isn't the same vendor. `nova-lite` takes the SIMPLE tier at
$0.063/1M in, about 4x cheaper than haiku-3. The classifier deliberately stays on haiku-3: 27/30 was
measured with that classifier, so swapping it would invalidate the result rather than be a free saving.

Still open: all 11 agents share one master key, so at the gateway they are indistinguishable and equally
privileged. Per-agent virtual keys are the next increment — the Postgres built here is their prerequisite.

## Key decisions

- **Plain Kubernetes manifests, not a Helm chart.** BerriAI ships a chart only inside their source repo;
  the installable "litellm-helm" charts are third-party mirrors, and BerriAI's own chart assumes a
  Postgres `migrations-job` this DB-less build doesn't want.
- **Stateful since 2026-09-26** (`postgres.yaml`). It buys exactly one thing: enforcement. Deliberately
  *not* kagent's bundled Postgres — that one is chart-managed and backs agent memory (domain 8), and
  sharing it would put the model plane and the memory plane in one blast radius. Single replica, no HA:
  if it is down the gateway loses the *guard*, not service, because LiteLLM serves happily without a DB
  (that is precisely the unenforced state measured above).
- **All Bedrock, no API keys anywhere.** Credentials come from EKS Pod Identity: the `litellm`
  ServiceAccount is bound to the `aria-bedrock` role (`infra/02-eks/litellm.tf`). The only secret left is
  the proxy's own master key.
- **Native Langfuse callback**, not kagent's OTel path — it needs split
  `LANGFUSE_PUBLIC_KEY`/`LANGFUSE_SECRET_KEY`, so it's a separate Secrets Manager entry
  (`aria/litellm-langfuse`) even though it lands in the same `aria` project. One observability plane,
  two instrumentation paths.
- **Not MCP/`kmcp`-reconciled.** LiteLLM has no CRD here. It's a plain Deployment/Service referenced from
  `ModelConfig.spec.openAI.baseUrl` as a literal URL.

## The Azure removal (2026-09-18) — what broke and why

The Azure OpenAI resource backing `default-model-config` was **deleted**, not merely key-revoked:
`oai-ladp-ncs-4.openai.azure.com` returned `NXDOMAIN` from inside the cluster. Every declarative agent
lost its model at once (`cluster-diagnostics` → `API_ERROR`, `"Connection error."`), and
`kubectl get modelconfig` still reported `ACCEPTED=True` for the dead configs throughout. The failure was
only visible by calling an agent.

The fleet was repointed onto this gateway rather than onto Bedrock ModelConfigs directly, so there is one
place to change a model and one place where per-agent cost shows up.

**Three things this exposed, all fixed, all worth remembering:**

1. **A namespace quota sized to exactly one pod makes rolling updates impossible.** The v1 quota was
   `limits.cpu=1 / 1Gi` — one pod's worth. A RollingUpdate surges a second pod first, so the replacement
   was **rejected at admission** (`exceeded quota: compute-quota`), not left Pending: the ReplicaSet never
   got a pod object, backed off, and the gateway ended up with **zero** running pods, taking the fleet's
   model plane with it. Quota now fits two (`envs/dev.yaml`). Headroom here isn't slack, it's what makes
   the Deployment updatable.
2. **Then it was genuine node capacity.** Two `t3.large` nodes sat at 96–97% of CPU *requests*, one at its
   35-pod ENI ceiling, so a single 100m pod couldn't schedule. Resolved by scaling the node group 2 → 3
   (now at ASG max). Note `kubectl top` does not work on this cluster — **metrics-server isn't installed**,
   so only *requests* are visible, never real utilisation.
3. **Prisma OOMKills the proxy at 1Gi, silently.** Wiring `DATABASE_URL` made LiteLLM load Prisma at
   boot, which does not fit in 1Gi. It produced **zero log output** — no traceback, nothing on stdout —
   and the only evidence was `exitCode 137 / OOMKilled` in the pod's `lastState` plus a liveness probe
   failing against a port nothing was listening on. An OOM during interpreter start looks exactly like a
   hung application. Raising the container limit alone was not enough either: the namespace LimitRange
   (`maxMemory`) and the ResourceQuota are two separate admission gates, and both had to move.
4. **Config changes need a pod restart.** LiteLLM reads `config.yaml` at startup. A ConfigMap edit alone
   leaves the running proxy serving the old model list, which surfaces as
   `Invalid model name passed in model=...` from agents.

## Mesh

The `litellm` namespace is ambient-enrolled. Inbound is restricted to the 13 agent identities in
`platform/istio/policies/litellm-allow-list.yaml`. **The "both sides" rule applies:** giving an agent
`modelConfig: litellm-gateway` without adding its ServiceAccount to that list gets it connection-reset at
the mesh, and the agent reports it as a plain API error. `kagent-controller` is deliberately not listed —
unlike MCP servers, nothing calls a `ModelConfig` endpoint at reconcile time. Re-verify that after any
kagent bump.

## Verified live

**2026-09-19 (v2, all-Bedrock):** proxy serves all 6 routes; `cluster-diagnostics` answered through the
gateway end to end (`PONG`, 3607 tokens); `smart-router` routed a simple prompt to Haiku 3 and a hard
reasoning prompt to Haiku 4.5; embeddings returned 1536 dims with no API key.

**2026-09-04 (v1, Azure):** mesh allow-list enforcement proven both ways (`default` SA → connection reset;
`cost-sentinel` SA → 200); Langfuse confirmed via its own API to hold LiteLLM's `litellm-acompletion`
traces alongside kagent's OTel traces in the same project; per-tenant attribution proven via `user`
(`tenant-a`/`tenant-b` separable), while `metadata.tags` is **silently stripped** without
`general_settings.allow_client_tags: true`. Full detail in the archived v1.

## Open items

- ~~The Auto Router is deployed but unproven.~~ **Measured 2026-09-19, results in
  `router-eval/results/`.** The default heuristic classifier escalated **0 of 14** hard prompts — the
  COMPLEX and REASONING tiers were never used. Offline scoring against the same scorer shows why: the
  hardest prompt scores 0.340 against a 0.35 boundary, and easy/hard score ranges overlap (a trivial
  "what port does the API server listen on" scores 0.300, same as hard prompts), so **no boundary tuning
  fixes it** — best achievable 77%, only by escalating nearly everything. Switching to
  `classifier_type: llm` (Haiku 3, the cheapest route) took it to **27/30 with 8/8 hard prompts
  correct** — that is the config now live. Cost caveat, measured: correct routing cost **1.8x** an
  all-Sonnet baseline, because escalating correctly means paying Opus prices for long answers. Routing
  is a quality mechanism here, not a cost one.
- **`litellm-smart-router` is not wired to any agent** — deciding that needs the eval results first.
- **Embeddings unexercised**: no agent currently sets `spec.declarative.memory`. When one does, confirm
  kagent's embedder accepts `provider: OpenAI` with a custom baseUrl, and note Cohere Embed v4's vector
  dimensions differ from the old `text-embedding-3-large`, so existing pgvector rows may need reindexing.
- **`allow_client_tags`** not enabled, so tag-based (as opposed to `user`-based) attribution is dropped.
- Per-tenant virtual keys with budgets, and fallback routing, both still need the Postgres this build
  deliberately skips.

## Changelog

| Version | Date | Change |
|---|---|---|
| v2.2 | 2026-09-24 | `default-model-config` repointed at the gateway, fixing kagent's 4 built-in agents (broken since the Azure deletion); allow-list 9 -> 13 principals |
| v3 | 2026-09-26 | Postgres added → budgets now actually enforce (429 proven); cross-family fallbacks proven by kill test; Amazon Nova family added, SIMPLE tier crosses to nova-lite; proxy 2Gi (Prisma OOMs at 1Gi) |
| v2.1 | 2026-09-19 | Auto Router measured (30-prompt eval): heuristic escalates nothing → switched to LLM classifier; metrics-server added cluster-side |
| v2 | 2026-09-19 | All-Bedrock after the Azure resource was deleted; fleet-wide adoption (9 agents); Auto Router added; Cohere embeddings; image → `v1.100.1`; quota fixed to allow rolling updates |
| v1 | 2026-09-04 | First build: Azure OpenAI only, DB-less, `cost-sentinel` the single consumer — archived |
