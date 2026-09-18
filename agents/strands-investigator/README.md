# strands-investigator — the Strands BYO agent

ARIA's second BYO agent. It performs the **same task** as `investigation-loop` against the **same
MCP tool server** on the **same cluster**. The single variable under test is **who owns the agent
loop**.

| | `investigation-loop` | `strands-investigator` |
|---|---|---|
| Framework | LangGraph | Strands (AWS) |
| Who decides the branch | **your code** — `should_continue`, unit-testable | **the model**, inside Strands' event loop |
| Control flow artifact | an explicit `StateGraph` | none — there is no graph to show |
| Model | Azure OpenAI `gpt-5.4-mini` | Bedrock `claude-sonnet-4-6` |
| Model credential | static key from a Secret | **EKS Pod Identity — no static key** |
| kagent glue | `kagent-langgraph`'s `KAgentApp` | `app.py` + `executor.py`, written here |

## Why there is no graph in this repo folder

That absence *is* the finding. LangGraph makes you author the loop, so the loop is a reviewable,
testable artifact. Strands is model-first: you supply a system prompt and tools, and the model decides
when to call a tool, when to loop, and when to stop. Same observable behaviour class; nothing of yours
to assert on.

## What it took to bring a new framework to kagent

kagent publishes `kagent-langgraph` but nothing for Strands. That sounds like "write an A2A server",
and it is not. `kagent-langgraph` is a thin adapter over **`kagent-core`**, which is framework-clean
(no langchain/langgraph imports anywhere in it). So the work is:

- **`executor.py`** — a `StrandsAgentExecutor(AgentExecutor)`. The only framework-specific file.
- **`app.py`** — assembles the FastAPI/A2A app. Exactly one line of it is Strands-specific; the rest
  (`KAgentTaskStore`, `KAgentRequestContextBuilder`, `DefaultRequestHandler`,
  `A2AStarletteApplication`) is reused verbatim from kagent-core and the a2a SDK.

Full reasoning and evidence: `aria/docs/spec-byo-frameworks.md` §3.

## The contract this image must satisfy

Bigger than `spec.byo`'s description admits ("serve A2A on port 8080"):

1. **A2A on `:8080`** — served by `A2AStarletteApplication`.
2. **`GET /.well-known/agent-card.json`** — this is the **readiness probe** kagent's controller
   configures for BYO pods. Serve A2A but not this, and the pod never goes Ready. Undocumented in
   the CRD; found by reading the rendered Deployment.

## Deploying

Three steps, in order — the first is infra and cannot be done from GitOps:

```bash
# 1. Bedrock Pod Identity (once). In infra/02-eks/terraform.tfvars:
#      enable_bedrock_pod_identity = true
#      agent_service_account       = "strands-investigator"
terraform -chdir=infra/02-eks apply

# 2. Build + push the image (see infra/04-persistent/README.md for the ECR repo)
aws ecr get-login-password --region ap-southeast-1 \
  | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com
docker build -t <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/aria/strands-investigator:latest .
docker push  <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/aria/strands-investigator:latest

# 3. Commit agent.yaml — ArgoCD's `agents` Application syncs it automatically.
```

An ECR repository `aria/strands-investigator` must exist; add it alongside the others in
`infra/04-persistent`.

## Verifying

```bash
kubectl -n kagent get agent strands-investigator          # Accepted=True, Ready=True
kubectl -n kagent exec deploy/strands-investigator -- \
  curl -s localhost:8080/.well-known/agent-card.json      # the readiness contract

# End to end, through the controller's A2A front door:
curl -X POST http://kagent-controller.kagent:8083/api/a2a/kagent/strands-investigator \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{
       "kind":"message","role":"user","messageId":"1",
       "parts":[{"kind":"text","text":"Why is incident-commander not Accepted?"}]}}}'
```

Expect a task whose `history[]` shows real `k8s_*` tool calls before any conclusion. An answer with no
tool calls in the history is the failure mode ARIA's eval loop exists to catch.

## Known limitations

- **Cancellation is not supported.** Strands exposes no mid-flight interrupt this executor can call, so
  `cancel()` reports `canceled` without actually stopping the loop. An honest cost of not owning the loop.
- **No streaming.** The agent card declares `streaming: false`; the executor returns one artifact at the
  end. `investigation-loop` streams. Worth closing later if the comparison needs it.
- **MCP session per request.** `executor.py` opens the MCP client inside `execute()` rather than holding
  it open, trading a little latency for not depending on a session surviving an idle pod.
