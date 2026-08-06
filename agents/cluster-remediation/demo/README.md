# HITL remediation demo — pause, approve, execute

Proves `cluster-remediation`'s human-in-the-loop gate live: a gated mutating tool (`k8s_scale`) **pauses**
for approval and only runs once you approve. Verified end-to-end 2026-08-03 (see
`../../../docs/platform-proposal-infraops-agents.md`).

## Setup

```sh
KCTX=arn:aws:eks:ap-southeast-1:622629043701:cluster/aria   # always pass --context (kubeconfig drifts)

# 1. Deploy the broken target (Deployment at 0 replicas)
kubectl --context "$KCTX" apply -f broken-app.yaml
kubectl --context "$KCTX" -n aria-demo get deploy broken-app        # -> 0/0

# 2. Reach the agent (port-forward is fine here — no AuthorizationPolicy on this agent)
kubectl --context "$KCTX" -n kagent port-forward svc/cluster-remediation 18081:8080 &
```

## Step 1 — ask it to fix the workload (it will PAUSE)

```sh
curl -s -X POST http://localhost:18081/ -H 'Content-Type: application/json' -d '{
  "jsonrpc":"2.0","id":"rem-1","method":"message/send",
  "params":{"message":{"kind":"message","messageId":"rem-msg-1","role":"user",
    "parts":[{"kind":"text","text":"The deployment named broken-app in namespace aria-demo has 0 replicas and is down. Bring it back to 1 replica."}]}}}'
```

Expect: the agent calls read tools, proposes the scale, then the Task comes back
**`"state":"input-required"`** with an `adk_request_confirmation` part:

```json
"toolConfirmation":{"hint":"Tool 'k8s_scale' requires approval before execution.","confirmed":false}
```

Confirm nothing ran — the deployment is still `0/0`:

```sh
kubectl --context "$KCTX" -n aria-demo get deploy broken-app        # still 0/0  <- the gate held
```

Grab `contextId`, `taskId`, and the confirmation call `id` ("adk-...") from that response for step 2.

## Step 2 — approve (it EXECUTES)

Resume on the **same `contextId`+`taskId`** with a `function_response` for `adk_request_confirmation`,
`confirmed: true` (use `false` to reject — the task ends without mutating):

```sh
curl -s -X POST http://localhost:18081/ -H 'Content-Type: application/json' -d '{
  "jsonrpc":"2.0","id":"rem-approve","method":"message/send",
  "params":{"message":{"kind":"message","messageId":"rem-approve-1","role":"user",
    "contextId":"<CONTEXT_ID>","taskId":"<TASK_ID>",
    "parts":[{"kind":"data",
      "data":{"id":"<ADK_CONFIRMATION_ID>","name":"adk_request_confirmation","response":{"confirmed":true}},
      "metadata":{"kagent_type":"function_response"}}]}}}'
```

Expect: Task → **`"state":"completed"`**, and the agent self-verifies the recovery. Confirm live:

```sh
kubectl --context "$KCTX" -n aria-demo get deploy broken-app        # -> 1/1 Running
```

## Reset / cleanup

```sh
kubectl --context "$KCTX" -n aria-demo scale deploy/broken-app --replicas=0   # re-arm the demo
# or remove entirely:
kubectl --context "$KCTX" delete -f broken-app.yaml
```

## What this demonstrates
- The `requireApproval` gate is enforced by kagent, not the prompt: the mutation is physically held.
- Approval is an **A2A `input-required` + tool-confirmation resume**, so it works headlessly (a client/
  eval can drive it), not only via the kagent UI.
- **Honest caveat:** the scale executes via the cluster-admin `kagent-tools` SA — approval gates *intent*,
  not the executor's *authority*. Scoping that RBAC is the tracked follow-up.
