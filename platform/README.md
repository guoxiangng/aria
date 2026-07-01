# platform/ — the reusable spine (D1–D4)

Build-once layer every agent inherits. Filled in after the cluster is up.

- `kagent/` — kagent install (Helm values), ModelConfig → Bedrock (global inference profile)
- `agent-template/` — Helm chart emitting the kagent Agent CR + scoped SA/RBAC + OTel + `requireApproval` + labels
- `tool-servers/` — scoped MCP tool servers, each with its own ServiceAccount
- `observability/` — Langfuse / OTel
- `policies/` — Kyverno admission policies

> See `docs/platform-proposal-infraops-agents.md` for the design.
