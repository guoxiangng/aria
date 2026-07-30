# Identity plane — rogue-agent deny demo

The faithful test that the [`cluster-diagnostics-allow-list`](../policies/cluster-diagnostics-authz.yaml)
`AuthorizationPolicy` actually enforces: a real in-mesh peer with a **valid but non-allow-listed SPIFFE
identity** is denied at the node ztunnel, while the one allow-listed identity gets through — same request,
same target, identity the only variable.

## Why not just `kubectl port-forward`?

Because it proves nothing. `port-forward` (and `kubectl exec ... curl localhost`) lands on the target
pod's **loopback**, which ztunnel does not intercept — so mesh authorization never runs and you get a
misleading `200`. The only faithful test originates from a **separate pod, over the pod network**, so
ztunnel sees the caller's mTLS identity and applies the policy. That is what these two probe pods do.

## The experiment

| Probe | ServiceAccount | SPIFFE identity | Expected |
|---|---|---|---|
| `authorized-probe` | `incident-commander` | `spiffe://cluster.local/ns/kagent/sa/incident-commander` | **HTTP 200** (on allow-list) |
| `rogue-probe` | `shadow-agent` | `spiffe://cluster.local/ns/kagent/sa/shadow-agent` | **TCP reset** (valid identity, not allow-listed) |

Both pods run identical `curlimages/curl` containers in the ambient-enrolled `kagent` namespace, so both
are full mesh members with real cryptographic identities. The deny is L4 (the policy matches only on
source principal), so ztunnel enforces it by **resetting the connection** — `curl` exits `56`, there is
no HTTP status. Absence of a status *is* the deny.

## Run it

```sh
export KCTX=arn:aws:eks:ap-southeast-1:622629043701:cluster/aria
kubectl --context "$KCTX" apply -f rogue-agent-demo.yaml
kubectl --context "$KCTX" -n kagent wait --for=condition=Ready pod/rogue-probe pod/authorized-probe --timeout=90s
KCTX="$KCTX" sh run-demo.sh
# when done — do NOT leave the rogue workload running:
kubectl --context "$KCTX" delete -f rogue-agent-demo.yaml
```

## Observed result (2026-07-30)

```
PROBE 1 authorized-probe (incident-commander) → HTTP_CODE=200 EXIT=0
PROBE 2 rogue-probe       (shadow-agent)       → curl: (56) Recv failure: Connection reset by peer
                                                  HTTP_CODE=000 EXIT=56
```

ztunnel access log on the destination node, the two connections side by side:

```
info  access  connection complete  src.workload="authorized-probe"
      src.identity="spiffe://cluster.local/ns/kagent/sa/incident-commander"
      dst.service="cluster-diagnostics..." direction="inbound" bytes_sent=3907 bytes_recv=356

error access  connection complete  src.workload="rogue-probe"
      src.identity="spiffe://cluster.local/ns/kagent/sa/shadow-agent"
      dst.service="cluster-diagnostics..." direction="inbound" bytes_sent=0 bytes_recv=0
      error="connection closed due to policy rejection: allow policies exist, but none allowed"
```

The rogue agent was not blocked by network position, a firewall, or a missing password — it was blocked
because it **cryptographically is not the one identity allowed to make that call**. That is zero-trust
for agent-to-agent traffic, enforced.

> This is a test workload, not part of the ArgoCD app-of-apps — a deliberately-rogue pod should never run
> permanently. Apply to demonstrate, then delete.
