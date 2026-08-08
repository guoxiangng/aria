# platform/kagent — kagent runtime + models

kagent is an **operator**: installing it (Helm) deploys the **CRDs** (`Agent`, `ModelConfig`,
`ToolServer`/`RemoteMCPServer`, …) and the **controller** that reconciles them. After install, you bring in
agents/models/tools by **applying CRs** — same on EKS or OpenShift.

Files here:
- `values.yaml` — overlay on the upstream `kagent` chart (single-node EKS tuning + Azure OpenAI provider)
- `modelconfig-bedrock.yaml` — extra Bedrock `ModelConfig`s (`bedrock-sonnet`, `bedrock-haiku`)

## Install

```bash
# 1. CRDs
helm install kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
  --namespace kagent --create-namespace

# 2. Azure OpenAI API key secret (NOT committed) — referenced by values.yaml providers block
kubectl create secret generic kagent-azure-openai \
  --from-literal=AZUREOPENAI_API_KEY=<your-key> -n kagent

# 3. Controller + built-ins + Azure default provider
helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent -f values.yaml

# 4. Extra Bedrock ModelConfigs (after the provider decision below)
kubectl apply -f modelconfig-bedrock.yaml
```
Fill in your Azure `azureDeployment` + `azureEndpoint` in `values.yaml` first.
Check chart values: `helm show values oci://ghcr.io/kagent-dev/kagent/helm/kagent`.

## Models available to agents
| ModelConfig | Provider | Auth | Notes |
|---|---|---|---|
| `default-model-config` | Azure OpenAI (`gpt-4o`) | `kagent-azure-openai` secret | chart-created; known-good default |
| `bedrock-sonnet` | Bedrock (Claude Sonnet 4.6) | **Pod Identity, no key** | preferred once verified |
| `bedrock-haiku` | Bedrock (Claude Haiku 4.5) | Pod Identity | cheap; eval-judge / high-volume |

An `Agent` picks one via `spec.declarative.modelConfig: <name>`. Good practice: run agents on one provider,
the **eval-judge on another** (model diversity).

## Bedrock provider — DECIDE AT INSTALL (Azure works meanwhile)
kagent's chart has no Bedrock provider entry, so Bedrock is wired via our own `ModelConfig` CRs. Paths, best-first:
1. **Native `provider: Bedrock` + Pod Identity (no key)** — *verify kagent's ADK runtime supports the Bedrock
   provider via the AWS credential chain.* Needs `controller.agentDeployment.serviceAccountName` (or per-agent SA)
   = the Pod-Identity-bound SA, and `enable_bedrock_pod_identity=true` in `infra/02-eks/terraform.tfvars`.
2. **OpenAI-compat Bedrock endpoint** (`provider: OpenAI`, `baseUrl=…/openai/v1`) + a Bedrock API key — works,
   but static key.
3. **LiteLLM proxy** — agents talk OpenAI to a LiteLLM pod that assumes a Pod-Identity role for Bedrock.

## Bringing in agents (the operator/CR workflow)
1. Author (or reuse) an `Agent` CR under `agents/<name>/`. Your AIDA agents port over — adjust `namespace`,
   `modelConfig`, and sub-agent/tool refs. (Reference: `git/aida-platform-agent-configs/telecom-multi-agent/`.)
2. Apply it — `kubectl apply` now; later rendered via `charts/agent-template/` and delivered by Helm/ArgoCD.
3. The controller reconciles it into a running agent pod (A2A endpoint), reusing a `ModelConfig` above.

ARIA's `charts/agent-template/` will generate these CRs from values + a content-pack (baking D1–D4) — the
upgrade over hand-writing each CR.

## Image repository (ECR) — NOT needed yet
kagent + built-in agents pull upstream (`cr.kagent.dev`/ghcr); Declarative agents run no custom image. ECR is
only for **BYO container agents** (the RAG agent, later) → add `infra/persistent/ecr.tf` (durable layer) then.

## Reference (AIDA patterns)
- Full vendored chart (all knobs) → `git/aida-ckn-deploy/kagent/`
- ModelConfig + Agent CR shapes → `git/aida-platform-agent-configs/telecom-multi-agent/`
- kagent secret + ArgoCD placeholder trick → `git/cak-platform-cac/operator-configs/kagent/`

## Long-term memory (pgvector, self-hosted) — live 2026-08-08

kagent has **two** memory paths; don't conflate them:

| Path | Backend | Status here |
|---|---|---|
| `Memory` CR | **Pinecone only** (`provider` enum has one value) — external SaaS | not used |
| `spec.declarative.memory` on an Agent | kagent's **own Postgres via pgvector** | **in use** |

### What was needed
1. `database.postgres.vectorEnabled: true` (ships disabled).
2. **A pgvector-capable Postgres image.** The chart's bundled image is stock `postgres:18.3-alpine`, where
   the extension isn't even installable (`select count(*) from pg_available_extensions where name='vector'`
   returned `0`). With the flag on and that image, the controller crash-loops:
   `database migration failed … vector migrations require pgvector`. Swapped to `pgvector/pgvector:pg18` —
   same Postgres major version, so the existing PVC data directory stayed compatible (image swap, not a
   migration). Extension then installed: `vector|0.8.6`. Data intact (13 tables).
3. An **embedding** ModelConfig — `modelconfig-azure-embedding.yaml` (`text-embedding-3-large`). The chat
   model cannot vectorize. Its key comes from Secrets Manager via ESO (`kagent-azure-embedding`); the value
   was written with the CLI, never through tfvars/TF state (see `infra/03-argocd/eso.tf`).

### The gotcha: memory is scoped per user, and A2A invents a user per conversation
Calling an agent's A2A endpoint **directly** (unauthenticated) makes every new conversation a new user, so
long-term recall silently never hits. From upstream `converters/request_converter.py`:

```python
def _get_user_id(request):
    if request.call_context and request.call_context.user and request.call_context.user.user_name:
        return request.call_context.user.user_name    # auth enabled
    return f"A2A_USER_{request.context_id}"           # fallback
```

Verified: a planted fact was stored under `A2A_USER_<contextId-A>` and a fresh conversation searched under
`A2A_USER_<contextId-B>` → `No memories found`.

**Working invocation** — through the controller with a stable user identity:

```bash
curl -X POST http://kagent-controller.kagent:8083/api/a2a/kagent/<agent> \
  -H 'X-User-Id: <stable-user>' -H 'Content-Type: application/json' -d '{...message/send...}'
```

Proven: session 1 stored "lucky colour is teal"; a **new** session as the same user recalled it; a
**different** user got "I don't know" (correct isolation). Takeaway: **memory is downstream of identity.**

### Capacity note
Enabling this forced a Postgres reschedule that could not fit ("Insufficient cpu" / "Too many pods"), taking
the DB down until unused built-in agents were disabled (see `values.yaml`). On small clusters the built-in
agent fleet — one Deployment each — is the real constraint.
