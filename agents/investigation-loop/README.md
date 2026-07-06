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

## Run locally (NOT yet deployed to the cluster — see Status below)
```bash
cd agents/investigation-loop
uv sync                    # or: pip install -e .
cp .env.example .env       # fill in the Azure key

# reach kagent-tools from your laptop:
kubectl -n kagent port-forward svc/kagent-tools 8084:8084

uv run python -m investigation_agent.main "a pod keeps restarting intermittently in namespace kagent"
```

## Status: experiment, not yet deployed
This is Python code you can run locally right now. It is **not yet**:
- containerized (needs a `Dockerfile`)
- pushed anywhere (needs **ECR** — first time ARIA needs it; see `docs/repo-structure.md`'s deferred-work
  note on `infra/persistent/`, since ECR images must survive `terraform destroy` of the EKS layer)
- registered as a `kagent` `BYO` Agent CR (`spec.type: BYO`, `spec.byo.deployment.image: <ecr-image>`)
- wired into `incident-commander` as a delegate

Those are the deliberate next steps once this local experiment proves the pattern is worth deploying —
not done in this pass, to keep the infra and the agent-logic decisions separate and reviewable on their
own merits.
