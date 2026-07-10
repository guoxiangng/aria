# eval/ — agent eval loop

Built on [promptfoo](https://promptfoo.dev) (open-source CLI, no cloud dependency required).
One config per agent, run either locally (via port-forward, for iterating on a rubric) or as a
Kubernetes Job inside the cluster (real in-cluster Service DNS, used by CI).

## Files

- `*.promptfooconfig.yaml` — one per agent, covering the scenarios in `docs/scenarios.md` that
  target it. `cluster-diagnostics` and `incident-commander` grade a **groundedness gate**: every
  agent response is graded not just on whether the final answer sounds right, but on whether its
  claims actually trace back to the tool calls it made (see `transforms/a2a-with-evidence.js`) —
  catches a confidently-wrong answer that a text-only rubric would pass.
- `transforms/a2a-with-evidence.js` — extracts both the tool-call evidence (args + results,
  correlated by call id) and the final answer from a kagent A2A `message/send` response, so the
  judge sees what was actually checked, not just what was said.
- `Dockerfile` / `run-all.sh` — packages the runner as a container; `run-all.sh` points each
  config at the real in-cluster Service (`<agent>.kagent:8080`) instead of the `localhost:1808X`
  port-forwards used for local runs.
- `job.yaml` — Kubernetes Job template (CI substitutes image tag + run id, applies directly —
  not ArgoCD-managed, since Jobs are one-shot, not a persistent app).

## Known limitation: investigation-loop

`investigation-loop` (the hand-built BYO LangGraph agent) exposes **only its final answer** in
the A2A response — no tool-call breadcrumbs like the ADK-based agents. Its config can grade
answer plausibility, but **cannot verify scenario 6's real acceptance criterion** (did it
actually cycle gather→hypothesize→verify→loop, or answer on the first pass?). That needs a
different mechanism — querying the Langfuse trace's span tree for the invocation, or grepping pod
logs for LLM call counts (as was done manually earlier in this project). Not yet built.

## Running locally

```
kubectl port-forward -n kagent svc/<agent> 1808X:8080   # see each config's header for the port
export AZURE_API_KEY=$(kubectl get secret kagent-azure-openai -n kagent -o jsonpath='{.data.AZUREOPENAI_API_KEY}' | base64 -d)
export AZURE_API_HOST="oai-ladp-ncs-4.openai.azure.com"
npm install --no-save promptfoo   # first time only
./node_modules/.bin/promptfoo eval -c eval/<agent>.promptfooconfig.yaml --no-cache
```

## Running in CI

`.github/workflows/eval.yml` builds the image, applies `job.yaml` as a Job in the `kagent`
namespace, waits for completion, and fails the check on the Job's exit code. Uses a dedicated
write-scoped role (`aria-github-actions-eval`, `infra/01-bootstrap`) separate from the read-only
role used elsewhere in CI — namespace-scoped to `kagent` only, not cluster-admin.

## Not yet built

- RAG-style engines (Ragas/DeepEval) — not needed yet; the groundedness-via-tool-evidence
  approach above covers what the current scenarios need. Revisit if a future agent's evaluation
  needs retrieval-specific metrics (context precision/recall) rather than tool-call groundedness.
- Guardrail/red-team scenarios (G1-G3 in `docs/scenarios.md`) — different test shape (pass/fail on
  refusal behavior, not a quality rubric); promptfoo or garak/PyRIT could cover this, not started.
