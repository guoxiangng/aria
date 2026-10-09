# Evidence — a rogue agent is denied on identity alone

- **Captured:** 2026-07-30 · Istio 1.30.3 ambient · re-confirmed unchanged 2026-09-18
- **Source:** `platform/istio/test/` (`rogue-agent-demo.yaml` + `run-demo.sh` + its README)
- **Establishes:** agent-to-agent authorization is enforced cryptographically, not by network position.

## The setup

Two pods, **identical containers**. The only difference is which ServiceAccount they run as, and
therefore which SPIFFE identity their traffic carries. Both call the same agent on the same port.

## The result

```
PROBE 1 authorized-probe (incident-commander) → HTTP_CODE=200 EXIT=0
PROBE 2 rogue-probe       (shadow-agent)       → curl: (56) Recv failure: Connection reset by peer
                                                  HTTP_CODE=000 EXIT=56
```

The destination node's ztunnel log, both connections side by side:

```
info  access  connection complete  src.workload="authorized-probe"
      src.identity="spiffe://cluster.local/ns/kagent/sa/incident-commander"
      dst.service="cluster-diagnostics..." direction="inbound" bytes_sent=3907 bytes_recv=356

error access  connection complete  src.workload="rogue-probe"
      src.identity="spiffe://cluster.local/ns/kagent/sa/shadow-agent"
      dst.service="cluster-diagnostics..." direction="inbound" bytes_sent=0 bytes_recv=0
      error="connection closed due to policy rejection: allow policies exist, but none allowed"
```

`bytes_recv=0` is the whole point: the rogue call never reached the application.

## Honest limits

- **The deny is L4** — the policy matches on source principal only. It authorizes *who may call*, not
  *which A2A method* they may invoke. Method-level rules would need a waypoint proxy.
- **Absence of a status code is the deny.** A policy rejection is indistinguishable, to the caller, from
  a dead peer or a network blip — it surfaces as a TCP reset, not a 403. The authorization failure is
  only legible in the *destination's* ztunnel log.
- **The identity is a ServiceAccount**, so anyone who can create a pod in the namespace with that SA can
  mint the allow-listed identity. The boundary moves to Kubernetes RBAC, it doesn't disappear.
- The rogue workload is deliberately **not** in the ArgoCD app-of-apps. Apply, demonstrate, delete.

## Why it was rebuilt

The first version of this test "passed" and proved nothing: it used `kubectl port-forward`, which
tunnels to the pod's loopback interface, where ambient's ztunnel never intercepts. A green result from a
harness that bypasses the thing being tested. The faithful test needed a real in-mesh peer with its own
identity — which is what the two probes above are.
