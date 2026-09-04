# platform/litellm — model gateway (domain 10)

ARIA's first model-gateway layer: a self-hosted [LiteLLM](https://docs.litellm.ai/) proxy sitting in
front of Azure OpenAI, giving agents an OpenAI-compatible endpoint instead of calling the provider
directly. Fills the gap `aria/docs/ARCHITECTURE.md` §2 listed as `❌ not built`, and is the first real
build under `LADP/docs/direction-2-llm-gateway-observability.md`.

**Only `cost-sentinel` is wired through it today** (`agents/cost-sentinel/agent.yaml`). Every other agent
still calls `default-model-config`/Bedrock directly — additive, not a fleet-wide cutover.

## Key decisions

- **Plain Kubernetes manifests, not a Helm chart.** BerriAI (LiteLLM's maintainer) ships the chart only
  inside their own source repo (`deploy/charts/litellm-helm/`) — there's no first-party `helm repo add`
  or OCI source the way kagent has `ghcr.io/kagent-dev/kagent/helm`. The only installable
  "litellm-helm" charts are third-party mirrors (RichardoC, chetankapoor, Unique AG), and BerriAI's own
  chart templates assume a Postgres `DATABASE_URL` (a `migrations-job.yaml`) that this build's DB-less
  decision doesn't want. Hand-written `deployment.yaml`/`service.yaml`/`configmap.yaml` avoid both the
  third-party supply-chain question and the DB assumption.
- **DB-less v1.** LiteLLM's dynamic virtual-key/budget API (`/key/generate`, per-key spend) needs
  Postgres. Not worth the infra for one provider and one consuming agent. v1 uses a single master key
  (`general_settings.master_key`); per-tenant attribution comes from tagging requests
  (`user`/`metadata`) and reading them back in Langfuse, not from LiteLLM's own key store. Per-tenant
  *virtual keys* with DB-backed budgets are a flagged follow-up, not a blocker — see Open items below.
- **Azure OpenAI only.** Reuses the exact secret kagent's own `default-model-config` already calls
  (`aria/kagent-azure-openai` in Secrets Manager) — no new IAM grant for it. Bedrock/Kimi/Alicloud
  entries in `model_list` are explicitly deferred ("next time", per the build decision).
- **Native Langfuse callback**, not kagent's OTel/collector path. LiteLLM's built-in
  `success_callback: ["langfuse"]` wants split `LANGFUSE_PUBLIC_KEY`/`LANGFUSE_SECRET_KEY` env vars —
  a different shape than `kagent-langfuse-otel`'s composed Basic-Auth header, so it's a **separate**
  Secrets Manager secret (`aria/litellm-langfuse`, TF-seeded from the same
  `langfuse_public_key`/`langfuse_secret_key` tfvars) even though it lands in the same Langfuse `aria`
  project. One observability plane, two instrumentation paths.
- **Not MCP/`kmcp`-reconciled.** LiteLLM has no CRD here — it's a plain Deployment/Service, referenced
  from `platform/kagent/modelconfig-litellm.yaml`'s `openAI.baseUrl` as a literal in-cluster URL. Worth
  stating plainly: this project has twice shipped confusion about which controller reconciles which CRD
  (`MCPServer` vs `kagent-controller` vs `kmcp` — `aria/docs/ARCHITECTURE.md` §4). LiteLLM doesn't
  belong to that question at all.

## Files here

| File | What |
|---|---|
| `configmap.yaml` | LiteLLM's `config.yaml` — the `model_list` entry (Azure OpenAI via the `azure-gpt-5-4-mini` alias), `general_settings.master_key`, `litellm_settings.success_callback` |
| `deployment.yaml` | `ServiceAccount` + `Deployment` — hardened baseline (`runAsNonRoot`, `readOnlyRootFilesystem`, capabilities dropped), envFrom the 3 secrets below |
| `service.yaml` | ClusterIP `litellm.litellm.svc.cluster.local:4000` |

Secrets consumed (materialized by ESO — see `platform/external-secrets/manifests/`):

| Secret (in `litellm` ns) | Source | Used for |
|---|---|---|
| `litellm-azure` | `aria/kagent-azure-openai` (reused, same secret kagent uses) | `AZURE_API_KEY` |
| `litellm-langfuse` | `aria/litellm-langfuse` (new, TF-seeded) | `LANGFUSE_PUBLIC_KEY`/`LANGFUSE_SECRET_KEY` |
| `litellm-master-key` | `aria/litellm-master-key` (new, container-only — seeded via CLI, see `infra/03-argocd/eso.tf`) | `LITELLM_MASTER_KEY` |

A fourth ExternalSecret, `litellm-gateway-key` (in the **`kagent`** namespace, not `litellm`), points at
the same `aria/litellm-master-key` secret — `ModelConfig.apiKeySecret` is namespace-scoped and agent
pods run in `kagent`, so the master key needs a second in-namespace copy for `modelconfig-litellm.yaml`
to reference.

## Mesh

`litellm` namespace is ambient-enrolled (`envs/dev.yaml`). Inbound restricted to `cost-sentinel`'s SPIFFE
identity only — `platform/istio/policies/litellm-allow-list.yaml`. Deliberately does **not** allow
`kagent-controller` (unlike the MCP-server allow-lists): the controller has no reconcile-time call
against a `ModelConfig`'s endpoint the way `kagent-kmcp-controller-manager` does an `initialize` call
against every `MCPServer` — inference calls happen from the agent pod itself, at runtime. Re-verify this
holds after any kagent version bump before trusting it (this project has been burned by an unverified
"the controller doesn't need this" assumption before).

## `[VERIFY]` — all resolved live, 2026-09-04

- [x] Image tag `ghcr.io/berriai/litellm:v1.83.14-stable` — confirmed to exist live via the ghcr.io
      registry API (anonymous pull token + manifest HEAD), not assumed. Re-check for a newer stable tag
      if this sits unbuilt for long — BerriAI cuts weekly stable releases.
- [x] `ModelConfig` field shapes (`provider: OpenAI`, `openAI.baseUrl`, top-level
      `apiKeySecret`/`apiKeySecretKey`) — confirmed live via `kubectl explain modelconfig.spec
      --recursive` against the running 0.10.0-rc1 CRD.
- [x] Pod reaches `Ready` — `litellm-7c79f9876-p85tn`, `1/1 Running`, health probes returning 200.
- [x] A real Azure completion round-trips through the proxy — confirmed twice: a direct
      `/v1/chat/completions` call from an in-mesh probe, and (after fixing the rollout below) a genuine
      `cost-sentinel` A2A question, whose 3 LLM calls appear in LiteLLM's own logs at the exact same
      timestamps as the A2A task's tool-use loop.
- [x] `AuthorizationPolicy` denies a non-`cost-sentinel` caller — probe pod as `default` SA got
      `Connection reset by peer` (HTTP_CODE 000); the identical probe as `cost-sentinel` SA got HTTP 200.
- [x] Langfuse shows the trace landing under LiteLLM's own callback (`litellm-acompletion`), queried live
      via the Langfuse public API — and, worth noting, kagent's own OTel traces (`POST /`) show up
      alongside it in the same query: real confirmation this is one project, two instrumentation paths,
      not an assumption.
- [x] Two `user=`-tagged calls show separable attribution in Langfuse — **`userId` works**
      (`tenant-a`/`tenant-b` came through cleanly, queried live), **`metadata.tags` does not**: LiteLLM
      logged `Stripped caller-supplied tags from metadata: this key/team does not have
      allow_client_tags: true` and the traces confirm it — `tags: []` on both. So the DB-less "two
      tenants" story from `LADP/docs/direction-2-*.md` is proven via `user`, not via tags as originally
      assumed. Fix (not yet applied): add `general_settings.allow_client_tags: true` to
      `configmap.yaml` if tag-based attribution is wanted later.

## Real findings from the live build (2026-09-04)

- **The `cost-sentinel` repoint didn't take effect until a stuck rollout was manually unstuck.**
  Changing `Agent.spec.declarative.modelConfig` triggered a new ReplicaSet (config-hash changed) as
  expected, but the new pod sat `Pending` for 9+ minutes — `0/2 nodes are available: 1 Too many pods, 2
  Insufficient cpu`. The cluster's 2×t3.large node pair is genuinely near its pod-count ceiling (30/35,
  32/35 at the time). A surge rollout on a capacity-constrained cluster can silently stall rather than
  fail loud — the Agent CR, the ModelConfig, and the Deployment's pod template all looked correct the
  whole time; only `kubectl describe pod` on the *new* pod showed the real blocker. Resolved by deleting
  the old pod manually to free room; the rollout then completed normally. Worth remembering for the next
  increment that adds a workload here — this cluster has little headroom left.
- **ArgoCD app refresh lag, not a wave-ordering bug.** `external-secrets-config` (wave 1) initially
  didn't pick up the new `ExternalSecret` manifests even after `litellm` (wave 2) had already synced the
  same commit — each `Application` polls its own path on its own schedule, wave ordering doesn't force a
  simultaneous re-poll across apps on a fresh commit. A `kubectl annotate application ...
  argocd.argoproj.io/refresh=hard` forced it immediately; otherwise it would have caught up within the
  default poll interval on its own.

## Open items (deferred, not blocking)

- Per-tenant **virtual keys** with DB-backed budgets — needs `general_settings.database_url`
  (Postgres). Would either reuse kagent's bundled pgvector Postgres (couples lifecycles) or stand up a
  dedicated one. Not scoped for this increment.
- Bedrock / Kimi / Alicloud `model_list` entries — same shape as the existing Azure entry, deferred per
  the build decision ("next time").
- Fallback routing (kill a model, prove automatic failover) — Direction 2's stretch demo goal, not
  attempted in v1.
