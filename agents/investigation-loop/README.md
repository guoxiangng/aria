# investigation-loop — ARIA's first BYO (non-kagent-native) agent

A hand-built **LangGraph `StateGraph`** — not a kagent Declarative agent, not the `create_agent`
convenience wrapper. The point is to demonstrate what those two don't give you cleanly: an explicit,
**bounded cycle**:

```
gather_evidence → hypothesize → verify_hypothesis ─┬─> conclude   (confidence high enough, or
                       ↑                            │              max_iterations reached)
                       └────────────────────────────┘
                         (loop back if unconfirmed)
```

Test scenario: `docs/scenarios.md` #6 — the acceptance test is that it **visibly iterates** (gather →
hypothesize → verify → loop) rather than answering on the first pass, and that the loop is bounded
(never spins forever — the "loop engineering" principle: cap iterations, always terminate).

## Why LangGraph here, and not kagent Declarative
kagent's Declarative agents (`cluster-diagnostics`, `incident-commander`) are a great fit for
single-shot ReAct-style tool use. LangGraph is a better fit when the control flow itself is the point —
explicit states, conditional loops, (later) human-in-the-loop interrupts. This agent is the "why
LangGraph" proof point; a future `remediation-with-approval` agent will use LangGraph's `interrupt`
support for actual human approval gates (see `docs/scenarios.md` and the platform roadmap).

## Design choices
- **Reuses kagent's existing MCP tool server** (`kagent-tools`) via `langchain-mcp-adapters` — no new
  tool implementation, no duplicated infra.
- **Same read-only tool allowlist as `cluster-diagnostics`** — this BYO agent is also diagnostic-only,
  no mutating tools. Consistent security posture across kagent-native and BYO agents.
- **Same Azure model** as the rest of ARIA (env vars match the team's LADP `.env` naming exactly).

## Run locally (fastest way to iterate on the graph logic)
```bash
cd agents/investigation-loop
uv sync                    # or: pip install -e .
cp .env.example .env       # fill in the Azure key

# reach kagent-tools from your laptop:
kubectl -n kagent port-forward svc/kagent-tools 8084:8084

uv run python -m investigation_agent.main "a pod keeps restarting intermittently in namespace kagent"
```
This path uses `main.py` directly — no A2A server, no kagent SDK, no checkpointer. Good for fast
iteration on the graph itself before touching the deployment path.

## Deploy to the cluster (the real A2A path)
Uses `agent.py` + `cli.py` (kagent's official `kagent-langgraph` SDK — `KAgentApp` wraps the graph as
an A2A server) + `Dockerfile`, pushed to ECR, registered via `agent.yaml` (`spec.type: BYO`).

```bash
# 1. one-time: create the ECR repo (infra/04-persistent — durable, survives cluster teardown)
cd infra/04-persistent && terraform init -backend-config=backend.hcl && terraform apply

# 2. build + push (see infra/04-persistent/README.md for the exact commands)
cd ../../agents/investigation-loop
docker build -t <account>.dkr.ecr.ap-southeast-1.amazonaws.com/aria/investigation-loop:latest .
docker push <account>.dkr.ecr.ap-southeast-1.amazonaws.com/aria/investigation-loop:latest

# 3. agent.yaml is already committed - ArgoCD picks it up automatically (gitops/apps/agents.yaml).
#    Before the image is pushed, the pod sits in ImagePullBackOff - expected, self-resolving.
kubectl -n kagent get pods -l kagent=investigation-loop
```

## Status
- Graph logic: done, syntax-checked, locally runnable.
- Deployment path (Dockerfile, ECR via Terraform, `agent.py`/`cli.py` using kagent's official SDK,
  `agent.yaml` BYO CR): done, committed.
- **Not yet verified**: an actual successful run through the real A2A path (image hasn't been built/pushed
  yet — that's a manual step requiring local `docker`/`aws` CLI access, done outside this session).
- **Not yet wired**: as a delegate under `incident-commander` (straightforward once the above is verified
  working — just add a `type: Agent` tool entry pointing at `investigation-loop`).
- **Not yet verified**: whether kagent's controller injects the same platform-level `OTEL_*` env vars into
  BYO deployments as it does Declarative ones (see the note in `cli.py`) — check Langfuse for a trace after
  the first real invocation.
