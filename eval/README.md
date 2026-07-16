# eval/ — agent eval loop

Built on [promptfoo](https://promptfoo.dev) (open-source CLI, no cloud dependency required).
One config per agent, run either locally (via port-forward, for iterating on a rubric) or on a
self-hosted CI runner living inside the cluster (real in-cluster Service DNS, used by CI).

## Files

- `*.promptfooconfig.yaml` — one per agent, covering the scenarios in `docs/scenarios.md` that
  target it. `cluster-diagnostics` and `incident-commander` grade a **groundedness gate**: every
  agent response is graded not just on whether the final answer sounds right, but on whether its
  claims actually trace back to the tool calls it made (see `transforms/a2a-with-evidence.js`) —
  catches a confidently-wrong answer that a text-only rubric would pass.
- `transforms/a2a-with-evidence.js` — extracts both the tool-call evidence (args + results,
  correlated by call id) and the final answer from a kagent A2A `message/send` response, so the
  judge sees what was actually checked, not just what was said.
- `run-all.sh` — swaps each config's `localhost:1808X` (local dev, via port-forward) for the real
  in-cluster Service DNS (`<agent>.kagent:8080`), then runs every config, exiting non-zero if any
  suite fails.

An earlier approach (build an image, push to ECR, apply it as a one-shot Kubernetes Job from a
GitHub-hosted runner, poll for completion across the network) was retired after a full session's
worth of debugging exactly that cross-network polling — IAM gaps, wait-condition logic, timeouts,
transient kubectl failures, all traceable to the runner not living in the cluster. Replaced by
the ARC-based approach below; the old `Dockerfile`/`job.yaml` and their IAM role/EKS access entry
have been removed.

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

`.github/workflows/eval.yml` runs on a self-hosted GitHub Actions runner (Actions Runner
Controller, `platform/arc/`) living inside the `arc-runners` namespace in the cluster - not a
GitHub-hosted runner. Since the runner pod is already on the cluster network, the workflow just
checks out the repo and runs `eval/run-all.sh` directly; no image build/push/apply-and-poll
indirection at CI time.

The runner pool uses a **custom image** (`platform/arc/runner.Dockerfile`) with Node.js +
promptfoo pre-baked in, not the plain `ghcr.io/actions/actions-runner` image. Measured: a fresh
`npm install promptfoo` (571 transitive packages, no cache) hung past 20 minutes under the
runner pod's CPU limits - baking it into the image once (rebuilt only when bumping promptfoo's
version) avoids paying that cost on every single CI run:
```
docker build -f platform/arc/runner.Dockerfile -t 622629043701.dkr.ecr.ap-southeast-1.amazonaws.com/aria/eval-runner:ci-runner platform/arc
docker push 622629043701.dkr.ecr.ap-southeast-1.amazonaws.com/aria/eval-runner:ci-runner
```

Setup (one-time, not git-managed): create the GitHub PAT secret ARC authenticates with -
```
kubectl create secret generic arc-gha-pat -n arc-runners --from-literal=github_token='ghp_...'
```
(classic PAT, `repo` scope - fine-grained tokens aren't a documented/supported path for ARC).

See `platform/arc/runner-values.yaml` for the runner pool config, and `envs/dev.yaml` for why
`arc-runners` is a separate namespace from `kagent` (isolation over convenience, a deliberate
trade-off for a PoC - it means the Azure OpenAI secret is duplicated into `arc-runners` rather
than referenced directly). The runner authenticates to the cluster as a normal in-cluster
ServiceAccount, not an external IAM identity - no AWS IAM role is needed for CI at all anymore.

## Not yet built

- RAG-style engines (Ragas/DeepEval) — not needed yet; the groundedness-via-tool-evidence
  approach above covers what the current scenarios need. Revisit if a future agent's evaluation
  needs retrieval-specific metrics (context precision/recall) rather than tool-call groundedness.
- Guardrail/red-team scenarios (G1-G3 in `docs/scenarios.md`) — different test shape (pass/fail on
  refusal behavior, not a quality rubric); promptfoo or garak/PyRIT could cover this, not started.
