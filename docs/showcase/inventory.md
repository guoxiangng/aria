# Inventory — what is actually running

> Captured live from the `aria` EKS cluster. **Refresh this from `kubectl`, never from memory.**
> Commands are in each section so the next pass is a re-run, not a re-derivation.

**Captured:** 2026-10-09 · kagent `0.10.0-rc1` · 14 namespaces · 48 deployments · all 26 pods in
`kagent` at `1/1`

---

## Agents — 13

`kubectl -n kagent get agents -o custom-columns=NAME:.metadata.name,TYPE:.spec.type`

| Agent | Type | Tier | Tools wired |
|---|---|---|---|
| `incident-commander` | Declarative | `3-orchestrator` | 5 sub-agents as tools: cluster-diagnostics, cloud-diagnostics, cost-sentinel, deploy-diagnostics, investigation-loop |
| `cluster-diagnostics` | Declarative | `1-readonly` | kagent-tool-server (8), aws-documentation (2) |
| `cloud-diagnostics` | Declarative | `1-readonly` | aws-eks (7) |
| `cost-sentinel` | Declarative | `1-readonly` | aws-pricing (7) |
| `deploy-diagnostics` | Declarative | `1-readonly` | github (12) |
| `investigation-loop` | **BYO** (LangGraph) | `2-byo` | own loop — code-decided branching |
| `strands-investigator` | **BYO** (Strands) | `2-byo` | own loop |
| `infra-author` | Declarative | `2-propose` | terraform (7), github-write (5) |
| `cluster-remediation` | Declarative | `2-remediation` | kagent-tool-server (7) — **requireApproval** on mutating tools |
| `k8s-agent`, `helm-agent`, `istio-agent`, `promql-agent` | Declarative | kagent built-ins | kagent-tool-server (18 / 9 / 20 / —) |

Tiers are ARIA's own label (`aria.dev/tier`), not a kagent concept. Two BYO agents means the
container contract has now been exercised by **two** different frameworks.

## MCP servers — 6, all Ready

`kubectl -n kagent get mcpserver,remotemcpserver`

| Server | Hosted by | Scope |
|---|---|---|
| `aws-eks` | kmcp | EKS insights, VPC/subnets, CloudWatch — read-only |
| `aws-pricing` | kmcp | live AWS Pricing |
| `aws-documentation` | kmcp | AWS docs — needs no cloud identity at all |
| `github` | kmcp | **read-only** PAT; 6 agents depend on that being read-only |
| `github-write` | kmcp | write scope, **one** repo, fine-grained PAT — a separate server on purpose |
| `terraform` | kmcp | `--toolsets registry` only: provider/module schema lookups, no apply path |
| `kagent-tool-server` | kagent | the built-in tool server (`RemoteMCPServer`) |

## Model access — gateway is fleet-wide

`kubectl -n kagent get modelconfig` · `kubectl -n litellm get deploy`

Every one of the 11 **declarative** agents now reaches models through the in-cluster LiteLLM gateway —
7 of ARIA's own via `litellm-gateway`, and kagent's 4 chart-managed built-ins via `default-model-config`,
which itself now points at the gateway. The 2 BYO agents bypass it.

| ModelConfig | Provider | Model |
|---|---|---|
| `litellm-gateway` | OpenAI-compatible → LiteLLM | `bedrock-haiku-4-5` |
| `default-model-config` | OpenAI-compatible → LiteLLM | `bedrock-haiku-4-5` |
| `litellm-smart-router` | OpenAI-compatible → LiteLLM | `smart-router` |
| `litellm-embedding` | OpenAI-compatible → LiteLLM | `cohere-embed-v4` |
| `bedrock-haiku`, `bedrock-sonnet` | Bedrock (direct) | haiku-4-5 / sonnet-4-6 |
| `azure-embedding` | AzureOpenAI | `text-embedding-3-large` — **stale**, the Azure resource was deleted |

`litellm` 1/1 (35d) + `litellm-postgres` 1/1 (13d) — no longer the DB-less v1. An agent also needs its
ServiceAccount on `litellm-allow-list.yaml` or it is reset at the mesh.

## Platform components

| Namespace | What runs there |
|---|---|
| `kagent` | controller, kmcp controller, UI, Postgres (pgvector), tool server, 13 agents, 6 MCP servers — 25 deployments |
| `litellm` | the model gateway + its Postgres |
| `istio-system` | ambient mesh — istiod, ztunnel (DaemonSet), istio-cni |
| `argocd` | GitOps — 6 deployments, app-of-apps |
| `external-secrets` | ESO → AWS Secrets Manager |
| `ate-system` | Agent Substrate — 5 deployments |
| `agent-sandbox-system` | Agent Sandbox (SIG) controller |
| `arc-systems`, `arc-runners` | self-hosted ephemeral CI runners |
| `aria-agents-dev`, `aria-demo` | dev/demo surfaces |

**Isolation probes:** `substrate-probe` Ready. The `agent-sandbox-probe` is no longer present — Agent
Sandbox's controller still runs, but nothing is currently pinned to it.

---

## Not built — deliberately listed

| | Why it's here |
|---|---|
| `charts/agent-template/` (the golden template) | per-agent config is still hand-rolled |
| Kyverno admission policies | governance at deploy time, next up |
| Argo Rollouts | **not installed** — so eval-gated progressive delivery has no canary half |
| Claude Agent SDK as a BYO agent | third framework, not attempted |
| Least-privilege RBAC for the tool server | the honest open gap — see `evidence/approval-held-a-mutation.md` |
