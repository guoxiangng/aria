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
